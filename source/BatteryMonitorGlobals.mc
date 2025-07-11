using Toybox.Application as App;
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

    return [now, battery, solar];
}

(:glance)
function analyzeAndStoreData(data, dataSize) {
	//DEBUG*/ logMessage("analyzeAndStoreData");

	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
    var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
	var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
	var history = App.getApp().mHistory;
	var historySize = App.getApp().mHistorySize;
	var added = 0;

	if (lastHistory == null || history == null) { // no data yet (if we haven't got a last history, we can safely assume history was also empty)
		history = new [0];
		for (var dataIndex = 0; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
			if (isSolar) {
				history.addAll([data[dataIndex][TIMESTAMP], data[dataIndex][BATTERY], data[dataIndex][SOLAR]]); // As long as we didn't reach the end of our allocated space, keep adding
			}
			else {
				history.addAll([data[dataIndex][TIMESTAMP], data[dataIndex][BATTERY]]); // As long as we didn't reach the end of our allocated space, keep adding
			}
		}

		// Tell the App this is our history now
		var ret = App.getApp().setHistory(history);
		history = ret[0];
		historySize = ret[1];

		lastHistory = data[dataSize - 1];
		added = dataSize;
		//DEBUG*/ logMessage("First addition (" + added + ") " + data);
	}
	else { // We have a history and a last history, see if the battery value is different than the last and if so, store it
		var screenWidth = Sys.getDeviceSettings().screenWidth;
		var maxSize = (screenWidth * 4 > HISTORY_MAX ? HISTORY_MAX : screenWidth * 4);
		var dataIndex;
		for (dataIndex = 0; dataIndex < dataSize; dataIndex++) {
			if (lastHistory[BATTERY] != data[dataIndex][BATTERY]) { // Look for the first new battery level since last time
				break; // Found it!
			}
			else {
				//DEBUG*/ logMessage("Ignored " + data[dataIndex]);
			}
		}

		var historyRefresh = false;
		//DEBUG*/ var addedData = []; logMessage("historySize " + historySize + " dataSize " + dataSize);
		for (; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
			if (historySize >= maxSize) { // We've reached the max size, average the bottom half of the array so we have room too grow without affecting the latest data. If there are too many entries, we may need to come back here and do it all over
				var newSize = maxSize / 2 + maxSize / 4;
				var newHistory = new [newSize * elementSize]; // Shrink by 25%
				//DEBUG*/ logMessage("Making room for new entries. From " + historySize + " down to " + newSize);

				for (var i = 0, j = 0; j < historySize; i++) {
					if (j < historySize / 2) {
						newHistory[i * elementSize + TIMESTAMP] = history[j * elementSize + TIMESTAMP] + (history[(j + 1) * elementSize + TIMESTAMP] - history[j * elementSize + TIMESTAMP]) / 2;
						newHistory[i * elementSize + BATTERY] = history[j * elementSize + BATTERY] + (history[(j + 1) * elementSize + BATTERY] - history[j * elementSize + BATTERY]) / 2;
						if (isSolar) {
							newHistory[i * elementSize + SOLAR] = history[j * elementSize + SOLAR] + (history[(j + 1) * elementSize + SOLAR] - history[j * elementSize + SOLAR]) / 2;
						}

						j += 2;
					}
					else if (i < newSize) {
						newHistory[i * elementSize + TIMESTAMP] = history[j * elementSize + TIMESTAMP];
						newHistory[i * elementSize + BATTERY] = history[j * elementSize + BATTERY];
						if (isSolar) {
							newHistory[i * elementSize + SOLAR] = history[j * elementSize + SOLAR];
						}
						j++;
					}
					else { // If our history was bigger than the allowed space somehow, or because of rounding errors, keep adding the end of the new history until we've exhausted all data in history
						if (isSolar) {
							newHistory.addAll([history[j * elementSize + TIMESTAMP], history[j * elementSize + BATTERY], history[j * elementSize + SOLAR]]); // As long as we didn't reach the end of our allocated space, keep adding
						}
						else {
							newHistory.addAll([history[j * elementSize + TIMESTAMP], history[j * elementSize + BATTERY]]); // As long as we didn't reach the end of our allocated space, keep adding
						}
						j++;
					}
				}

				// Now set that as our history and keep adding to it.
				history = newHistory;
				historySize = history.size() / elementSize;
				newHistory = null; // Clear it out to reclaim space
				historyRefresh = true;
			}

			if (history[((historySize - 1) * elementSize) + BATTERY] != data[dataIndex][BATTERY]) {
				if (isSolar) {
					history.addAll([data[dataIndex][TIMESTAMP], data[dataIndex][BATTERY], data[dataIndex][SOLAR]]); // As long as we didn't reach the end of our allocated space, keep adding
				}
				else {
					history.addAll([data[dataIndex][TIMESTAMP], data[dataIndex][BATTERY]]); // As long as we didn't reach the end of our allocated space, keep adding
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
		objectStorePut("LAST_HISTORY_KEY", lastHistory);
		App.getApp().setHistoryModified(true);
	}
}

(:glance)
function downSlope() { //data is history data as array / return a slope in percentage point per second
	var app = App.getApp();
	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
    var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
	var size = app.mHistorySize;
	var data = app.mHistory;

	//DEBUG*/ Sys.print("["); for (var i = 0; i < size; i++) { Sys.print(data[i]); if (i < size - 1) { Sys.print(","); } } Sys.println("]");

	//DEBUG*/ logMessage(data);
	if (size <= 2) {
		return null;
	}

	// Don't run too often, it's CPU intensive!
	var lastRun = objectStoreGet("LAST_SLOPE_CALC", 0);
	var now = Time.now().value();
	if (now < lastRun + 30) {
		var lastSlope = objectStoreGet("LAST_SLOPE_VALUE", null);
		if (lastSlope != null) {
			//DEBUG*/ logMessage("Retreiving last stored slope (" + lastSlope + ")");
			return lastSlope;
		}
	}
	objectStorePut("LAST_SLOPE_CALC", now);

	var slopes = new [0];

	var count = 0;
	var sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
	var arrayX = new [0];
	var arrayY = new [0];
	var keepGoing = true;
	var batDiff = data[(size - 1) * elementSize + BATTERY] - data[(size - 2) * elementSize + BATTERY];

	for (var i = size - 1, j = i; i >= 0; i--) {
		if (batDiff < 0) { // Battery going down or staying level (or we are the last point in the dataset), build data for Correlation Coefficient and Standard Deviation calculation
			var diffX = data[j * elementSize + TIMESTAMP] - data[i * elementSize + TIMESTAMP];
			var battery = data[i * elementSize + BATTERY].toFloat() / 10.0;
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

			if (i == 0) {
				//DEBUG*/ logMessage("Stopping this serie because 'i == 0'");
				keepGoing = false; // We reached the end of the array, calc the last slope if we have more than one data
			}
			else if (i > 1) {
				batDiff = data[(i - 1) * elementSize + BATTERY] - data[(i - 2) * elementSize + BATTERY]; // Get direction of the next battery level for next pass
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
			var slope = r * (standardDeviationY / standardDeviationX);
			//DEBUG*/ logMessage("count=" + count + " sumX=" + sumX + " sumY=" + sumY.format("%0.3f") + " sumXY=" + sumXY.format("%0.3f") + " sumX2=" + sumX2 + " sumY2=" + sumY2.format("%0.3f") + " stdevX=" + standardDeviationX.format("%0.3f") + " stdevY=" + standardDeviationY.format("%0.3f") + " r=" + r.format("%0.3f") + " slope=" + slope);

			slopes.add(slope);

			// var diffY = data[i][BATTERY].toFloat() / 10.0 - data[j][BATTERY].toFloat() / 10.0;
			// var diffX = data[j][TIMESTAMP] - data[i][TIMESTAMP];
			// /*DEBUG*/ logMessage("count=" + count + " diffX=" + diffX + " sec (" + secToStr(diffX) + ") diffY=" + diffY.format("%0.3f") + "%");
			// if (diffX != 0) {
			// 	var slope = diffY / diffX;
			// 	/*DEBUG*/ logMessage("slope=" + slope);
			// 	slopes.add(slope);
			// }
		}

		// Reset of variables for next pass if we had something in them from last pass
		if (count > 0) {
			count = 0;
			sumXY = 0; sumX = 0; sumY = 0; sumX2 = 0; sumY2 = 0;
			arrayX = new [0];
			arrayY = new [0];
		}

		// Prepare for the next set of data
		j = i - 1;
		keepGoing = true;

		if (j > 1) {
			batDiff = data[j * elementSize + BATTERY] - data[(j - 1) * elementSize + BATTERY]; // Get direction of the next battery level for next pass
			//DEBUG*/ logMessage("i=" + j + " batDiff=" + batDiff);
		}
	}

	if (slopes.size() == 0){
		//DEBUG*/ logMessage("No slope to calculate");
		return null;
	}
	else {
		//DEBUG*/ logMessage("Slopes=" + slopes);
		var sumSlopes = 0;

		// // Calc the total time these slopes have happened so we car prorate them
		// var time = 0;
		// for (var i = 0; i < slopes.size(); i++) {
		// 	time += slopes[i][1];
		// }
		for (var i = 0; i < slopes.size(); i++) {
			sumSlopes += slopes[i];
		}
		//DEBUG*/ logMessage("sumSlopes=" + sumSlopes);
		var avgSlope = sumSlopes / slopes.size();
		//DEBUG*/ logMessage("avgSlope=" + avgSlope);

		objectStorePut("LAST_SLOPE_VALUE", avgSlope); // Store it so we can retreive it quickly if we're asking too frequently

		return avgSlope;
	}
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

function getBatteryColor(battery) {
    var colorBat;

    if (battery >= 50) {
        colorBat = COLOR_BAT_OK;
    }
    else if (battery >= 30) {
        colorBat = COLOR_BAT_WARNING;
    }
    else if (battery >= 10) {
        colorBat = COLOR_BAT_LOW;
    }
    else {
        colorBat = COLOR_BAT_CRITICAL;
    }

    return colorBat;
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
	var clockTime = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
	var dateStr = clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
	Sys.println(dateStr + " : " + message);
}
