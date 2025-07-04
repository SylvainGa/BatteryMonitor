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

(:background)
function analyzeAndStoreData(data, dataSize){
	//DEBUG*/ logMessage("analyzeAndStoreData");

	var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
	var added = false;

	if (lastHistory == null) { // no data yet
	    Storage.setValue("HISTORY_KEY", data); // Skip ObjectStorePut to prevent pushing data back on the stack for no good reason
		lastHistory = data[data.size() - 1];
		added = true;
		/*DEBUG*/ logMessage("Added " + data);
	}
	else { // New battery value? Store it
	    var history = objectStoreGet("HISTORY_KEY", null);
		if (history == null) {
		    Storage.setValue("HISTORY_KEY", data); // Skip ObjectStorePut to prevent pushing data back on the stack for no good reason
			lastHistory = data[data.size() - 1];
			added = true;
			/*DEBUG*/ logMessage("Added " + data);
		}
		else {
			var screenWidth = Sys.getDeviceSettings().screenWidth;
			var maxSize = (screenWidth * 4 > HISTORY_MAX ? HISTORY_MAX : screenWidth * 4);
			var dataIndex;
			for (dataIndex = 0; dataIndex < dataSize; dataIndex++) {
				if (lastHistory[BATTERY] != data[dataIndex][BATTERY]) { // Look for the first new battery level since last time
					break; // Found it!
				}
				else {
					/*DEBUG*/ logMessage("Ignored " + data[dataIndex]);
				}
			}

			var historySize = history.size();
			/*DEBUG*/ logMessage("historySize " + historySize + " dataSize " + dataSize);
			for (; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
				if (historySize < maxSize) {
					history.add(data[dataIndex]); // As long as we didn't reach the end of our allocated space, keep adding
					/*DEBUG*/ logMessage("Added " + data[dataIndex]);
					historySize++;
					added = true;
				}
				else {
					// We've reached the max size, average the bottom half of the array so we have room too grow without affecting the latest data. If there are too many entries, we may need to come back here and do it all over
					var isSolar = (Sys.getSystemStats().solarIntensity == null ? false : true);
					var newSize = maxSize / 4 + maxSize / 2;
					var newHistory = new [newSize]; // Shrink by 25%
					/*DEBUG*/ logMessage("Making room for new entries. From " + historySize + " down to " + newSize);
					
					for (var i = 0, j = 0; j < historySize; i++) {
						if (j < historySize / 2) {
							newHistory[i] = new [isSolar && history[j].size() == 3 && history[j + 1].size() == 3 ? 3 : 2];
							newHistory[i][TIMESTAMP] = history[j][TIMESTAMP] + (history[j + 1][TIMESTAMP] - history[j][TIMESTAMP]) / 2; // Average the time between both events
							newHistory[i][BATTERY] = history[j][BATTERY] + (history[j + 1][BATTERY] - history[j][BATTERY]) / 2; // 
							if (newHistory[i].size() == 3) {
								newHistory[i][SOLAR] = history[j][SOLAR] + (history[j + 1][SOLAR] - history[j][SOLAR]) / 2; // Average the time between both events
							}
							j += 2;
						}
						else if (i < newSize) {
							newHistory[i] = new [isSolar && history[j].size() == 3 ? 3 : 2];
							newHistory[i][TIMESTAMP] = history[j][TIMESTAMP];
							newHistory[i][BATTERY] = history[j][BATTERY];
							if (newHistory[i].size() == 3) {
								newHistory[i][SOLAR] = history[j][SOLAR];
							}
							j += 1;
						}
						else { // For the odd occasion when we didn't reserve enough room because of rounding precision
							if (isSolar && history[j].size() == 3) {
								newHistory.add([history[j][TIMESTAMP] , history[j][BATTERY], history[j][SOLAR]]);
							}
							else {
								newHistory.add([history[j][TIMESTAMP] , history[j][BATTERY]]);
							}
							j += 1;
						}
					}

					// Now set that as our history and keep adding to it.
					history = newHistory;
					historySize = history.size();
				}
			}

			if (added == true) {
				Storage.setValue("HISTORY_KEY", history); // Skip ObjectStorePut to prevent pushing history back on the stack for no good reason. 
				lastHistory = history[historySize - 1];
			}
		}
	}

	if (added) {
		objectStorePut("LAST_HISTORY_KEY", lastHistory);
	}
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreGet(key, defaultValue) {
    //DEBUG*/ if (key.equals("HISTORY_KEY")) { return [[1751132513, 22874],[1751132813, 22076],[1751133113, 21192],[1751133222, 20830],[1751136099, 20098],[1751136373, 20049],[1751136679, 19366],[1751136765, 19095],[1751136790, 18992],[1751136884, 19596],[1751136946, 20485],[1751137090, 22681],[1751137142, 23569],[1751137372, 26654],[1751137382, 27090],[1751137682, 31511],[1751137982, 35920],[1751138038, 36792],[1751138131, 36561],[1751138199, 36500],[1751138287, 36483],[1751139100, 36343],[1751139365, 36319],[1751140000, 36150],[1751140300, 35842],[1751140585, 35792],[1751140590, 35751],[1751142101, 34649],[1751142162, 34505],[1751142401, 34106],[1751142485, 34094],[1751145402, 33658],[1751145469, 33645],[1751145486, 33621],[1751146602, 33271],[1751146880, 33234],[1751147180, 32745],[1751147221, 32642],[1751147365, 32605],[1751147665, 32103],[1751147965, 31577],[1751148265, 31034],[1751148469, 30639],[1751148702, 30302],[1751148919, 30265],[1751148962, 30162],[1751149002, 30096],[1751159206, 27682],[1751159372, 27604],[1751159506, 27361],[1751163408, 26448],[1751163636, 26382],[1751163707, 26280],[1751163883, 28118],[1751163936, 29006],[1751163979, 29442],[1751164149, 32091],[1751164236, 33415],[1751164536, 37807],[1751164836, 42229],[1751164929, 43553],[1751165136, 46662],[1751165436, 51100],[1751165550, 52872],[1751165736, 55533],[1751166036, 59967],[1751166336, 64400],[1751166636, 68834],[1751166936, 73255],[1751167236, 77626],[1751167536, 81904],[1751167561, 82315],[1751167593, 82430],[1751167620, 82381],[1751167777, 82200],[1751168038, 82134],[1751168808, 81776],[1751169074, 81752],[1751169099, 81686],[1751169234, 81534],[1751170225, 81019],[1751170237, 80978],[1751170259, 80917],[1751170292, 80876],[1751170419, 80736],[1751174540, 79629],[1751174561, 79592],[1751196115, 75673],[1751196252, 75632],[1751196324, 75541],[1751200017, 74887],[1751200120, 74875],[1751200617, 74719],[1751219217, 60662],[1751219516, 60596],[1751219572, 60505],[1751219590, 60440],[1751219673, 60493],[1751225219, 60],[1751225412, 60300],[1751225434, 60234],[1751225519, 60148],[1751226119, 60608],[1751226967, 65918],[1751227271, 65852],[1751228170, 66880],[1751228474, 67986],[1751229675, 70133],[1751229903, 70055],[1751229977, 69759],[1751232999, 68858],[1751233235, 68846],[1751233293, 68694],[1751233417, 68525],[1751234073, 68344],[1751234132, 68217],[1751234206, 68102],[1751234408, 67962],[1751234499, 67859],[1751237199, 67225],[1751237500, 67036],[1751237799, 66535],[1751237877, 66522],[1751237924, 66444],[1751252501, 51819],[1751252559, 51803],[1751252771, 51276],[1751253689, 51034],[1751254022, 50544]]; }
	//DEBUG*/ if (key.equals("HISTORY_KEY")) { return [[1751313777, 36331],[1751314002, 36047],[1751314270, 35883],[1751314302, 35805],[1751314902, 35484],[1751315007, 35455],[1751315047, 35381],[1751315169, 35200],[1751315202, 35147],[1751315502, 34982],[1751315802, 34855],[1751338602, 25922],[1751341002, 25149],[1751342204, 24573],[1751342504, 24351],[1751342804, 24162],[1751343039, 24042],[1751343066, 23993],[1751343237, 26382],[1751343366, 28143],[1751343666, 32539],[1751343966, 36936],[1751344266, 41344],[1751344437, 43553],[1751344566, 45765],[1751344866, 50187],[1751345166, 54608],[1751345466, 59029],[1751345766, 63462],[1751346066, 67896],[1751346366, 72317],[1751346666, 76750],[1751346736, 77639],[1751346816, 78757],[1751347011, 78420],[1751347069, 78268],[1751347086, 78202],[1751369812, 74912],[1751369993, 74875],[1751370026, 74834],[1751376712, 73588],[1751376831, 73575],[1751376892, 73473],[1751376899, 73411],[1751376956, 73358],[1751376959, 73292],[1751376996, 73218],[1751424444, 39029],[1751424731, 39004],[1751425030, 38206],[1751425330, 37347],[1751425630, 36446],[1751425930, 35587],[1751426230, 34698],[1751426530, 33839],[1751426580, 33645],[1751428015, 33325, 0],[1751428019, 33312, 0],[1751428145, 33193, 0],[1751453247, 27349, 0],[1751453261, 27332, 0],[1751453561, 26691, 0],[1751453861, 25819, 0],[1751454161, 24943, 0],[1751454461, 24083, 0],[1751454761, 23207, 0],[1751455061, 22336, 0],[1751455263, 21731, 0],[1751460292, 20649, 0],[1751460316, 20612, 0],[1751460447, 20497, 0],[1751460538, 20715, 0],[1751463615, 65942, 0],[1751463915, 70388, 0],[1751464215, 74834, 0],[1751464515, 79284, 0],[1751464815, 83730, 0],[1751465115, 87727, 0],[1751465415, 90565, 0],[1751465715, 92650, 0],[1751466015, 94242, 0],[1751466196, 95040, 0],[1751466315, 95500, 0],[1751466615, 96528, 0],[1751466828, 97133, 0],[1751466852, 97211, 0],[1751483848, 70043, 0],[1751484047, 69311, 0],[1751486549, 68821, 0],[1751486792, 68797, 0],[1751487092, 68151, 0],[1751487298, 67624, 0],[1751500954, 57034, 0],[1751501049, 56870, 0],[1751501196, 56755, 0],[1751502154, 56561, 0],[1751502249, 56533, 0]]; }
	//DEBUG*/ if (key.equals("HISTORY_KEY")) { return [[1751313777, 36331],[1751314002, 36047],[1751314270, 35883],[1751314302, 35805],[1751314902, 35484],[1751315007, 35455],[1751315047, 35381],[1751315169, 35200],[1751315202, 35147],[1751315502, 34982],[1751315802, 34855],[1751338602, 25922],[1751341002, 25149],[1751342204, 24573],[1751342504, 24351],[1751342804, 24162],[1751343039, 24042],[1751343066, 23993],[1751343237, 26382],[1751343366, 28143],[1751343666, 32539],[1751343966, 36936],[1751344266, 41344],[1751344437, 43553],[1751344566, 45765],[1751344866, 50187],[1751345166, 54608],[1751345466, 59029],[1751345766, 63462],[1751346066, 67896],[1751346366, 72317],[1751346666, 76750],[1751346736, 77639],[1751346816, 78757],[1751347011, 78420],[1751347069, 78268],[1751347086, 78202],[1751369812, 74912],[1751369993, 74875],[1751370026, 74834],[1751376712, 73588],[1751376831, 73575],[1751376892, 73473],[1751376899, 73411],[1751376956, 73358],[1751376959, 73292],[1751376996, 73218],[1751424444, 39029],[1751424731, 39004],[1751425030, 38206],[1751425330, 37347],[1751425630, 36446],[1751425930, 35587],[1751426230, 34698],[1751426530, 33839],[1751426580, 33645],[1751428015, 33325, 0],[1751428019, 33312, 0],[1751428145, 33193, 0],[1751453247, 27349, 0],[1751453261, 27332, 0],[1751453561, 26691, 0],[1751453861, 25819, 0],[1751454161, 24943, 0],[1751454461, 24083, 0],[1751454761, 23207, 0],[1751455061, 22336, 0],[1751455263, 21731, 0],[1751460292, 20649, 0],[1751460316, 20612, 0],[1751460447, 20497, 0],[1751460538, 20715, 0],[1751463615, 65942, 0],[1751463915, 70388, 0],[1751464215, 74834, 0],[1751464515, 79284, 0],[1751464815, 83730, 0],[1751465115, 87727, 0],[1751465415, 90565, 0],[1751465715, 92650, 0],[1751466015, 94242, 0],[1751466196, 95040, 0],[1751466315, 95500, 0],[1751466615, 96528, 0],[1751466828, 97133, 0],[1751466852, 97211, 0],[1751483848, 70043, 0],[1751484047, 69311, 0],[1751486549, 68821, 0],[1751486792, 68797, 0],[1751487092, 68151, 0],[1751487298, 67624, 0],[1751500954, 57034, 0],[1751501049, 56870, 0],[1751501196, 56755, 0],[1751502154, 56561, 0],[1751502249, 56533, 0],[1751504704, 89833, 0],[1751504800, 89759, 0],[1751505003, 89640, 0],[1751505991, 93522, 0],[1751506221, 93485, 0],[1751506229, 93473, 0],[1751506291, 93419, 0],[1751506588, 93382, 0],[1751506591, 93358, 0],[1751506887, 92724, 0],[1751506891, 92662, 0],[1751507187, 91992, 0],[1751507191, 91918, 0],[1751507487, 91223, 0],[1751507491, 91133, 0],[1751507661, 90734, 0],[1751507670, 90655, 0],[1751507712, 90606, 0],[1751507762, 90565, 0],[1751507791, 90491, 0],[1751508091, 90335, 0],[1751508126, 90322, 0],[1751508391, 89759, 0],[1751508425, 89681, 0],[1751508691, 88986, 0],[1751508725, 88908, 0],[1751508991, 88200, 0],[1751509025, 88114, 0],[1751509292, 87394, 0],[1751509325, 87316, 0],[1751509410, 87069, 0],[1751509891, 86954, 0],[1751510157, 86929, 0],[1751511992, 86711, 0],[1751512140, 86699, 0],[1751543508, 81916, 0],[1751543540, 81904, 0],[1751543570, 81867, 0],[1751547109, 81365, 0],[1751547251, 81353, 0],[1751547279, 81299, 0],[1751547315, 81250, 0],[1751547366, 81209, 0],[1751547409, 81147, 0],[1751550408, 80300, 0],[1751550469, 80283, 0],[1751550494, 80246, 0],[1751554009, 79539, 0],[1751554273, 79477, 0],[1751554333, 79387, 0],[1751554393, 79284, 0],[1751554453, 79193, 0],[1751554513, 79115, 0],[1751554573, 79025, 0],[1751554600, 79000, 0],[1751554909, 78885, 0],[1751555207, 78819, 0],[1751558810, 77446, 0],[1751559106, 77404, 0],[1751559119, 77355, 0],[1751559148, 77277, 0],[1751563631, 99795, 0],[1751563743, 99754, 0],[1751563931, 99693, 0],[1751563990, 99681, 0],[1751564050, 99567, 0],[1751564110, 99448, 0],[1751564170, 99362, 0],[1751564230, 99260, 0],[1751564290, 99158, 0],[1751564350, 99068, 0],[1751564410, 98978, 0],[1751567232, 98108, 17],[1751567319, 98071, 0],[1751567341, 98006, 0]]; }
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

(:background)
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

(:background)
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
		str = hours.toNumber() + (fullText ? " " + Ui.loadResource(Rez.Strings.Hour) + (hours >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) + " " : " ") + mins.format("%2d") + " " + Ui.loadResource(Rez.Strings.Minute) + (mins >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "") : Ui.loadResource(Rez.Strings.HourShort) + mins.format("%02d"));
	}
	else {
		var days = Math.floor(min / 60 / 24);
		var hours = Math.floor((min / 60) - days * 24);
		str = days.toNumber() + (fullText ? " " + Ui.loadResource(Rez.Strings.Day) + (days >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) + " " : " ") : Ui.loadResource(Rez.Strings.DayShort) + " ") + hours.toNumber() + (fullText ? " " + Ui.loadResource(Rez.Strings.Hour) + (hours >= 2 ? Ui.loadResource(Rez.Strings.PluralSuffix) : "") : Ui.loadResource(Rez.Strings.HourShort));
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


(:debug, :background)
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

(:release, :background)
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
