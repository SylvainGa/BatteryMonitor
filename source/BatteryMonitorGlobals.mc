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

(:background)
function analyzeAndStoreData(data){
	//DEBUG*/ logMessage("analyzeAndStoreData");
	var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
	if (lastHistory == null){ // no data yet
		objectStoreAdd("HISTORY_KEY", data);
	}
	else { // New battery value? Store it
		if (lastHistory[BATTERY] != data[BATTERY]){
			objectStoreAdd("HISTORY_KEY", data);
		}
	}
	objectStorePut("LAST_HISTORY_KEY", data);
	objectStorePut("COUNT", objectStoreGet("COUNT", 0) + 1);
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreAdd(key, newValue) {
    //DEBUG*/ logMessage("objectStoreAdd");
    var existingArray = objectStoreGet(key, []);
    if (newValue != null) {
    	if (!(existingArray instanceof Toybox.Lang.Array)) {//if not array (incl is null), then create first item of array
	        objectStorePut(key, [newValue]);
	    }
		else { //existing value is an array
			if (existingArray.size() >= HISTORY_MAX) {
                objectStorePut(key, existingArray.slice(1, HISTORY_MAX).add(newValue));
			}
			else {
                objectStorePut(key, existingArray.add(newValue));
			}
	    }
	}
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreGet(key, defaultValue) {
    //DEBUG*/ if (key.equals("HISTORY_KEY")) { return [[1751132513, 22874],[1751132813, 22076],[1751133113, 21192],[1751133222, 20830],[1751136099, 20098],[1751136373, 20049],[1751136679, 19366],[1751136765, 19095],[1751136790, 18992],[1751136884, 19596],[1751136946, 20485],[1751137090, 22681],[1751137142, 23569],[1751137372, 26654],[1751137382, 27090],[1751137682, 31511],[1751137982, 35920],[1751138038, 36792],[1751138131, 36561],[1751138199, 36500],[1751138287, 36483],[1751139100, 36343],[1751139365, 36319],[1751140000, 36150],[1751140300, 35842],[1751140585, 35792],[1751140590, 35751],[1751142101, 34649],[1751142162, 34505],[1751142401, 34106],[1751142485, 34094],[1751145402, 33658],[1751145469, 33645],[1751145486, 33621],[1751146602, 33271],[1751146880, 33234],[1751147180, 32745],[1751147221, 32642],[1751147365, 32605],[1751147665, 32103],[1751147965, 31577],[1751148265, 31034],[1751148469, 30639],[1751148702, 30302],[1751148919, 30265],[1751148962, 30162],[1751149002, 30096],[1751159206, 27682],[1751159372, 27604],[1751159506, 27361],[1751163408, 26448],[1751163636, 26382],[1751163707, 26280],[1751163883, 28118],[1751163936, 29006],[1751163979, 29442],[1751164149, 32091],[1751164236, 33415],[1751164536, 37807],[1751164836, 42229],[1751164929, 43553],[1751165136, 46662],[1751165436, 51100],[1751165550, 52872],[1751165736, 55533],[1751166036, 59967],[1751166336, 64400],[1751166636, 68834],[1751166936, 73255],[1751167236, 77626],[1751167536, 81904],[1751167561, 82315],[1751167593, 82430],[1751167620, 82381],[1751167777, 82200],[1751168038, 82134],[1751168808, 81776],[1751169074, 81752],[1751169099, 81686],[1751169234, 81534],[1751170225, 81019],[1751170237, 80978],[1751170259, 80917],[1751170292, 80876],[1751170419, 80736],[1751174540, 79629],[1751174561, 79592],[1751196115, 75673],[1751196252, 75632],[1751196324, 75541],[1751200017, 74887],[1751200120, 74875],[1751200617, 74719],[1751219217, 60662],[1751219516, 60596],[1751219572, 60505],[1751219590, 60440],[1751219673, 60493],[1751225219, 60],[1751225412, 60300],[1751225434, 60234],[1751225519, 60148],[1751226119, 60608],[1751226967, 65918],[1751227271, 65852],[1751228170, 66880],[1751228474, 67986],[1751229675, 70133],[1751229903, 70055],[1751229977, 69759],[1751232999, 68858],[1751233235, 68846],[1751233293, 68694],[1751233417, 68525],[1751234073, 68344],[1751234132, 68217],[1751234206, 68102],[1751234408, 67962],[1751234499, 67859],[1751237199, 67225],[1751237500, 67036],[1751237799, 66535],[1751237877, 66522],[1751237924, 66444],[1751252501, 51819],[1751252559, 51803],[1751252771, 51276],[1751253689, 51034],[1751254022, 50544]]; }

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
}
