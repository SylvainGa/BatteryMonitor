using Toybox.Application as App;
using Toybox.Activity;
using Toybox.Background;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Application.Storage;

(:glance)
function getData() {
    var stats = Sys.getSystemStats();
    var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
    var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
    var now = Time.now().value(); //in seconds from UNIX epoch in UTC

    if (Sys.getSystemStats().charging) {
        var chargingData = objectStoreGet("STARTED_CHARGING_DATA", null);
        if (chargingData == null) {
            objectStorePut("STARTED_CHARGING_DATA", [now, battery, solar]);
        }
    }
    else {
        objectStoreErase("STARTED_CHARGING_DATA");
    }

	var activityStartTime = Activity.getActivityInfo().startTime;
	if (activityStartTime != null) { // we'll hack the battery level to flag that an activity is running by 'ORing' 0x1000 (4096) to the battery level
		battery |= 0x1000;
	}

    return [now, battery, solar];
}

(:glance)
function analyzeAndStoreData(data, dataSize, storeAlways) {
	//DEBUG*/ logMessage("analyzeAndStoreData");

	if (data == null) {
		return 0;
	}
	
	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
    var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
	var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
	var history = App.getApp().mHistory;
	var historySize = App.getApp().mHistorySize;
	var added = 0;

	if (lastHistory == null) { // no data yet (if we haven't got a last history, we can safely assume history was also empty)
		for (var dataIndex = 0; dataIndex < dataSize && historySize < HISTORY_MAX; dataIndex++, historySize++) { // Now add the new ones (if any)
			history[historySize * elementSize + TIMESTAMP] = data[dataIndex][TIMESTAMP];
			history[historySize * elementSize + BATTERY] = data[dataIndex][BATTERY];
			if (isSolar) {
				history[historySize * elementSize + SOLAR] = data[dataIndex][SOLAR];
			}
		}

		// Tell the App this is our history now
		var ret = App.getApp().setHistory(history);
		history = ret[0];
		historySize = ret[1];

		lastHistory = data[dataSize - 1];
		added = dataSize;
		//DEBUG*/ logMessage("analyze: First addition (" + added + ") " + data);
	}
	else { // We have a history and a last history, see if the battery value is different than the last and if so, store it but ignore this is we ask to always store
		var dataIndex;
		for (dataIndex = 0; dataIndex < dataSize && storeAlways == false; dataIndex++) {
			if ($.stripMarkers(lastHistory[BATTERY]) != $.stripMarkers(data[dataIndex][BATTERY])) { // Look for the first new battery level since last time
				break; // Found it!
			}
			else {
				//DEBUG*/ logMessage("Ignored " + data[dataIndex]);
			}
		}

		var historyRefresh = false;
		//DEBUG*/ var addedData = []; logMessage("analyze: historySize " + historySize + " dataSize " + dataSize);
		for (; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
			if (historySize >= HISTORY_MAX) { // We've reached 500 (HISTORY_MAX), start a new array
				App.getApp().storeHistory(added > 0 || App.getApp().getHistoryModified() == true, data[dataIndex][TIMESTAMP]); // Store the current history if modified and create a new one based on the latest time stamp

				// Now start fresh
				history = null; // Clean up before asking for more space
				history = new [HISTORY_MAX * elementSize];
				historySize = 0;
				historyRefresh = true;
				App.getApp().setHistoryNeedsReload(true); // Flag so we can rebuild our full history based on the new history arrays
			}

			if (historySize == 0 || storeAlways || history[((historySize - 1) * elementSize) + BATTERY] != data[dataIndex][BATTERY]) {
				history[historySize * elementSize + TIMESTAMP] = data[dataIndex][TIMESTAMP];
				history[historySize * elementSize + BATTERY] = data[dataIndex][BATTERY];
				if (isSolar) {
					history[historySize * elementSize + SOLAR] = data[dataIndex][SOLAR];
				}

				historySize++;
				added++;

				//DEBUG*/ addedData.add(data[dataIndex]);
			}
			else {
				//DEBUG*/ logMessage("Ignored " + data[dataIndex]);
			}
		}

		//DEBUG*/ logMessage("Added (" + added + ") " + addedData);

		if (added > 0) {
			// Reset the whole App history array if we had to redo a new one because we outgrew it size (see above)
			if (historyRefresh == true) {
				var ret = App.getApp().setHistory(history);
				history = ret[0];
				historySize = ret[1];
			}
			else { // If we just added to it, we only need to recalc its size
				historySize = App.getApp().getHistorySize(); // getHistorySize recalcs mHistorySize
			}

			if (isSolar) {
				lastHistory = [history[(historySize - 1) * elementSize + TIMESTAMP], history[(historySize - 1) * elementSize + BATTERY], history[(historySize - 1) * elementSize + SOLAR]]; // TIMESTAMP, BATTERY, SOLAR
			}
			else {
				lastHistory = [history[(historySize - 1) * elementSize + TIMESTAMP], history[(historySize - 1) * elementSize + BATTERY]]; // TIMESTAMP, BATTERY
			}
		}
	}

	if (added > 0) {
		//DEBUG*/ logMessage("Added " + added + ". history now " + App.getApp().getHistorySize());
		objectStorePut("LAST_HISTORY_KEY", lastHistory);
		App.getApp().setHistoryModified(true);
		App.getApp().setFullHistoryNeedsRefesh(true);
	}

	return added;
}

(:glance)
function downSlope(fromInit) { //data is history data as array / return a slope in percentage point per second
	//DEBUG*/ var startTime = Sys.getTimer();
	//DEBUG*/ logMessage("Calculating slope");
	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
    var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
	var historyArraySize = historyArray.size();

	// for (var i = 0; i < historyArraySize; i++) {
	// 	$.objectStoreErase("SLOPES_" + historyArray[i]);
	// }

	var totalSlopes = [];
	var firstPass = true; // In case we have no history arrays yet, we still need to process our current in memory history
	var slopeNeedsCalc = false; // When we're done, we don't need to come back to calculate more slopes (beside the active history)
	for (var index = 0; index < historyArraySize || firstPass == true; index++) {
		firstPass = false;
		var slopes = null;
		var slopesStartPos = 0;
		if (historyArraySize > 0) {
			var slopesData = $.objectStoreGet("SLOPES_" + historyArray[index], null);
			if (slopesData != null) {
				slopes = slopesData[0];
				slopesStartPos = slopesData[1];
			} 
		}
		if (slopes == null || (slopesStartPos != HISTORY_MAX && (fromInit == false || historyArraySize <= 1 ))) { // Slopes not calculated yet for that array or the array isn't fully calculated (if from init, only use the prebuilt array if they are available otherwise calc for only one slope)
			var data;
			var size;
			if (index == historyArraySize - 1 || historyArraySize == 0) { // Last history is from memory
				data = App.getApp().mHistory;
				size = App.getApp().mHistorySize;
				//DEBUG*/ logMessage("History: size " + size + " start@" + slopesStartPos);
			}
			else {
				data = $.objectStoreGet("HISTORY_" + historyArray[index], null);
				//DEBUG*/ logMessage("Calculating slope for HISTORY_" + historyArray[index]);
				if (data == null) {
					//DEBUG*/ logMessage("Skipping because it can't be found");
					continue; // Skip this one if we can't read it. Can happen when arrays have been merged but not accounting for yet
				}
				size = $.findPositionInArray(data, 0, elementSize);
				slopesStartPos = 0;
			}

			if (size <= 2) {
				continue;
			}

			slopes = [];

			var count = 0;
			var sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
			var arrayX = [];
			var arrayY = [];
			var keepGoing = true;

			if (slopesStartPos >= size) { // Sanity check that we don't go over the size of our filled array
				slopesStartPos = 0;
				$.objectStoreErase("SLOPES_" + historyArray[index]);
			}

			var i = slopesStartPos, j = slopesStartPos;

			var bat1 = $.stripMarkers(data[slopesStartPos * elementSize + BATTERY]);
			var bat2 = $.stripMarkers(data[(slopesStartPos + (slopesStartPos < size - 1 ? 1 : 0)) * elementSize + BATTERY]); // Make sure we don't go over the max size of the array with that +1
			var batDiff = bat2 - bat1;

			for (; i < size; i++) {
				if (batDiff < 0) { // Battery going down or staying level (or we are the last point in the dataset), build data for Correlation Coefficient and Standard Deviation calculation
					var diffX = data[i * elementSize + TIMESTAMP] - data[j * elementSize + TIMESTAMP];
					var battery = $.stripMarkers(data[i * elementSize + BATTERY]) / 10.0;

					//DEBUG*/ logMessage("i=" + i + " batDiff=" + batDiff + " diffX=" + secToStr(diffX) + " battery=" + battery + " count=" + count);
					sumXY += diffX * battery;
					sumX += diffX;
					sumY += battery;
					sumX2 += (diffX.toLong() * diffX.toLong()).toLong();
					sumY2 += battery * battery;
					//DEBUG*/ logMessage("diffX=" + diffX + " diffX * diffX=" + diffX * diffX + " sumX2=" + sumX2 + " sumY2=" + sumY2);
					arrayX.add(diffX);
					arrayY.add(battery);
					count++;

					if (i == size - 1) {
						//DEBUG*/ logMessage("Stopping this serie because we've reached the end so calculate the last slope of this array");
						keepGoing = false; // We reached the end of the array, calc the last slope if we have more than one data
					}
					else if (i < size - 2) {
						bat1 = $.stripMarkers(data[(i + 1) * elementSize + BATTERY]);
						bat2 = $.stripMarkers(data[(i + 2) * elementSize + BATTERY]);
						batDiff = bat2 - bat1; // Get direction of the next battery level for next pass
					}
					else {
						//DEBUG*/ logMessage("Doing last data entry in the array");
						// Next pass is for the last data in the array, process it 'as is' since we were going down until then (leave batDiff like it was)
					}
				}
				else {
					keepGoing = false;
					//DEBUG*/ logMessage("Stopping at i=" + i + " batDiff=" + batDiff);
				}

				if (keepGoing) {
					continue;
				}

				if (count > 1) { // We reached the end (i == size - 1) or we're starting to go up in battery level, if we have at least two data (count > 1), calculate the slope
					var standardDeviationX = Math.stdev(arrayX, sumX / count);
					var standardDeviationY = Math.stdev(arrayY, sumY / count);
					var r = (count * sumXY - sumX * sumY) / Math.sqrt((count * sumX2 - sumX * sumX) * (count * sumY2 - sumY * sumY));
					var slope = -(r * (standardDeviationY / standardDeviationX));
					//DEBUG*/ logMessage("count=" + count + " sumX=" + sumX + " sumY=" + sumY.format("%0.3f") + " sumXY=" + sumXY.format("%0.3f") + " sumX2=" + sumX2 + " sumY2=" + sumY2.format("%0.3f") + " stdevX=" + standardDeviationX.format("%0.3f") + " stdevY=" + standardDeviationY.format("%0.3f") + " r=" + r.format("%0.3f") + " slope=" + slope);

					slopes.add(slope);
					totalSlopes.add(slope);

					if (fromInit) { // If running from the Initialisation function, stop after going through one downslope. We'll let the timer handle the others
						j = i + 1;
						slopeNeedsCalc = true; // Flag that we'll need to go in next time to finish up
						break;
					}
				}

				// Reset of variables for next pass if we had something in them from last pass
				if (count > 0) {
					count = 0;
					sumXY = 0; sumX = 0; sumY = 0; sumX2 = 0; sumY2 = 0;
					arrayX = new [0];
					arrayY = new [0];
				}

				// Prepare for the next set of data
				if (i == size - 1) {
					break; // We've reached the end of our array, don't touch 'j' so we can store it later on to point where we need to start again next time around
				}

				j = i + 1;
				keepGoing = true;

				if (j < size - 1) {
					bat1 = $.stripMarkers(data[j * elementSize + BATTERY]);
					bat2 = $.stripMarkers(data[(j + 1) * elementSize + BATTERY]);
					batDiff = bat2 - bat1; // Get direction of the next battery level for next pass
					//DEBUG*/ logMessage("i=" + j + " batDiff=" + batDiff);
				}
			}

			if (slopes.size() > 0) {
				//DEBUG*/ logMessage("Slopes=" + slopes /*+ " start " + (size != HISTORY_MAX ? j : HISTORY_MAX) + (historyArraySize > 0 ? " for HISTORY_" + historyArray[index] : " with no historyArray")*/);
				var slopesName;
				var posInHistory;
				if (size != HISTORY_MAX || historyArraySize == 0) { // We're working on the live history file and not a stored one
					slopesName = data[0 + TIMESTAMP];
					posInHistory = j; // j is the starting position of the last known serie of down movement in the array
				}
				else {
					slopesName = historyArray[index];
					posInHistory = HISTORY_MAX;
				}
				$.objectStorePut("SLOPES_" + slopesName, [slopes, posInHistory]);
			}

			if (index < historyArraySize - 1) {
				slopeNeedsCalc = true; // Flag that we need to come back for more HISTORY_... to be calculated
			}
			break;
		}
		else {
			totalSlopes.addAll(slopes);
		}
	}

	// If we have no slopes, return null
	var slopesSize = totalSlopes.size();
	if (slopesSize == 0) {
		return [null, true];
	}

	var sumSlopes = 0;
	for (var i = 0; i < slopesSize; i++) {
		sumSlopes += totalSlopes[i];
	}
	var avgSlope = sumSlopes / slopesSize;
	//DEBUG*/ logMessage("avgSlope=" + avgSlope);
	//DEBUG*/ var endTime = Sys.getTimer(); logMessage("downslope took " + (endTime - startTime) + "msec");

	return [avgSlope, slopeNeedsCalc];
}

(:glance)
function initDownSlope() {
	var downSlopeSec;
	var historyLastPos;

	var downSlopeData = $.objectStoreGet("LAST_SLOPE_DATA", null);
	if (downSlopeData != null) {
		downSlopeSec = downSlopeData[0];
		historyLastPos = downSlopeData[1];
	}
	if (downSlopeSec == null || historyLastPos != App.getApp().mHistorySize) { // onBackgroundData added data since we last ran our slope calc last time we ran the app
		var downSlopeResult = $.downSlope(true);
		downSlopeData = [downSlopeResult[0], App.getApp().mHistorySize];
		$.objectStorePut("LAST_SLOPE_DATA", downSlopeData);
	}
}

(:glance)
function findPositionInArray(array, index, elementSize) {
	// Are we empty?
	if (array[0 + TIMESTAMP] == null) {
		index = 0;
		//DEBUG*/ logMessage("index " + index + " because is empty");
	}

	// Are we full already?
	else if (array[(HISTORY_MAX - 1) * elementSize + TIMESTAMP] != null) {
		index = HISTORY_MAX;
		//DEBUG*/ logMessage("index " + index + " found at 500");
	}

	// Are we already at the right location?
	else if (index > 0 && array[(index - 1) * elementSize + TIMESTAMP] != null && array[(index) * elementSize + TIMESTAMP] == null) {
		index = index;
		//DEBUG*/ logMessage("index " + index + " is already at the right place");
	}

	// Have just moved by one?
	else if (index < HISTORY_MAX - 1 && array[index * elementSize + TIMESTAMP] != null && array[(index + 1) * elementSize + TIMESTAMP] == null) {
		index++;
		//DEBUG*/ logMessage("index " + index + " found at next");
	}

	// Use a variation of a binary search to find the size. Worst case will be 8 iterations
	else {
		//DEBUG*/ var oldHistorySize = index;
		var nextTest = ((HISTORY_MAX - index) * 10 / 2 + 5) / 10; // This is the same as x / 2.0 + 0.5 but without the floating performance point penalty
		var count = 0; 
		index += nextTest;
		while (nextTest > 0 && count < 16) { // Sanity check so we don't get stuck in an infinity loop. We should find out spot in 8 tries max so if we're taking double, assume the current index is now correct
			count++;
			nextTest = (nextTest * 10 / 2 + 5) / 10; // We're going to look in half the data so prepare that variable
			if (array[index * elementSize + TIMESTAMP] == null) { // If we're null, look down
				if (index > 0 && array[(index - 1) * elementSize + TIMESTAMP] != null) { // The one below us isn't null, we found our first none empty before null, index is our size
					break;
				}
				index -= nextTest;
			}
			else { // We have data, look up
				if (index < HISTORY_MAX - 1 && array[(index + 1) * elementSize + TIMESTAMP] == null) {  // The one above us is null, we found our first none empty before null, index + 1 is our size
					index++;
					break; 
				}
				index += nextTest;
			}
		}

		//DEBUG*/ logMessage("index " + index + " found in " + count + " tries, started at " + oldHistorySize);
	}

	return index;
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreGet(key, defaultValue) {
    var value = Storage.getValue(key);
    if ((value == null) && (defaultValue != null)) {
        value = defaultValue;
        Storage.setValue(key, value);
	}
    return value;
}

// Global method for putting a key value pair into the
// object store. This method doesn't do anything that
// setProperty doesn't do, but provides a matching function
// to the objectStoreGet method above.
(:background)
function objectStorePut(key, value) {
    Storage.setValue(key, value);
}

(:background)
function objectStoreErase(key) {
    Storage.deleteValue(key);
}

function timestampToStr(timestamp) {
	var timeMoment = new Time.Moment(timestamp);
	var date = Time.Gregorian.info(timeMoment, Time.FORMAT_MEDIUM);

	// Format time accoring to 24/12 hour format
	var timeStr;
	if (Sys.getDeviceSettings().is24Hour) {
		timeStr = Lang.format("$1$h$2$", [date.hour.format("%2d"), date.min.format("%02d")]);
	}
	else {
		var ampm = "am";
		var hours12 = date.hour;

		if (date.hour == 0) {
			hours12 = 12;
		}
		else if (date.hour > 12) {
			ampm = "pm";
			hours12 -= 12;
		}

		timeStr = Lang.format("$1$:$2$$3$", [hours12.format("%2d"), date.min.format("%02d"), ampm]);
	}

	// Format the date according to the language file
	var dateFormat = Ui.loadResource(Rez.Strings.MediumDateFormat);
	var dateStr = Lang.format(dateFormat, [date.day_of_week, date.day, date.month]);

	return [dateStr, timeStr];
}

(:glance)
function minToStr(min, fullText) {
	var str;
	if (min < 1){
		str = Ui.loadResource(Rez.Strings.Now);
	}
	else if (min < 60){
		str = min.toNumber() + (fullText ? " " + Ui.loadResource(Rez.Strings.Minute) + (min >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "") : Ui.loadResource(Rez.Strings.MinuteShort));
	}
	else if (min < 60 * 24) {
		var hours = Math.floor(min / 60);
		var mins = min - hours * 60;
		str = hours.toNumber() + (fullText ? (" " + Ui.loadResource(Rez.Strings.Hour) + (hours >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "") + (mins > 0 ? (" " + mins.format("%d") + " " + Ui.loadResource(Rez.Strings.Minute) + (mins >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "")) : "")) : (Ui.loadResource(Rez.Strings.HourShort) + (mins > 0 ? (" " + mins.format("%d") + Ui.loadResource(Rez.Strings.MinuteShort)) : "")));
	}
	else {
		var days = Math.floor(min / 60 / 24);
		var hours = Math.floor((min / 60) - days * 24);
		str = days.toNumber() + (fullText ? (" " + Ui.loadResource(Rez.Strings.Day) + (days >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "") + (hours > 0 ? (" " + hours.format("%d") + " " + Ui.loadResource(Rez.Strings.Hour) + (hours >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "")) : "")) : (Ui.loadResource(Rez.Strings.DayShort) + (hours > 0 ? (" " + hours.format("%d") + Ui.loadResource(Rez.Strings.HourShort)) : "")));
	}
	return str;
}

(:glance)
function stripMarkers(battery) {
	if (battery >= 2000 && battery < 4096) { // Old format
		return battery - 2000;
	}
	return battery & 0xfff; // Markers are bitwise operators. We need to be over 3000 (100% full plus activity) to not interfere with the old format so 0x1000 (4096) is activity marker and 0x2000 is time marker therefore 0xfff strips them.
}

(:glance)
function MAX (val1, val2) {
	if (val1 > val2){
		return val1;
	}
	else {
		return val2;
	}
}

(:glance)
function MIN (val1, val2) {
	if (val1 < val2){
		return val1;
	}
	else {
		return val2;
	}
}

function to_array(string, splitter) {
	var array = new [30]; //Use maximum expected length
	var index = 0;
	var location;

	do {
		location = string.find(splitter);
		if (location != null) {
			array[index] = string.substring(0, location);
			string = string.substring(location + 1, string.length());
			index++;
		}
	} while (location != null);

	array[index] = string;

	var result = new [index + 1];
	for (var i = 0; i <= index; i++) {
		result[i] = array[i];
	}
	return result;
}

(:debug, :glance)
function secToStr(sec) {
	var str;
	if (sec < 1) {
		str = "Now";
	}
	else if (sec < 60) {
		str = sec.toNumber() + "s";
	}
	else if (sec < 60 * 60 ) {
		var mins = Math.floor(sec / 60);
		var secs = sec - mins * 60;
		str = mins.toNumber() + "m" + secs.format("%02d") + "s";
	}
	else if (sec < 60 * 60 * 24) {
		var hours = Math.floor(sec / (60 * 60));
		var min = sec - hours * 60 * 60;
		var mins = Math.floor(min / 60);
		var secs = min - mins * 60;
		str = hours.toNumber() + "h" + mins.format("%02d") + "m" + secs.format("%02d") + "s";
	}
	else {
		var days = Math.floor(sec / (60 * 60 * 24));
		var hour = sec - days * 60 * 60 * 24;
		var hours = Math.floor(hour / (60 * 60));
		var min = hour - hours * 60 * 60;
		var mins = Math.floor(min / 60);
		var secs = min - mins * 60;
		str = days.toNumber() + "d " + hours.toNumber() + "h" + mins.format("%02d") + "m" + secs.format("%02d") + "s";
	}
	return str;
}

(:release, :glance)
function secToStr(sec) {
}

(:debug, :background)
function logMessage(message) {
	var clockTime = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
	var dateStr = clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
	Sys.println(dateStr + " : " + message);
}

(:release, :background)
function logMessage(message) {
	// var clockTime = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
	// var dateStr = clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
	// Sys.println(dateStr + " : " + message);
}
