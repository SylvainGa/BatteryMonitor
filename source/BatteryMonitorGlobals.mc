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
	else { //data already exists
		if (lastHistory[BATTERY] == data[BATTERY]){
			var history = objectStoreGet("HISTORY_KEY", null);
			if (history != null) {
				history[history.size() - 1][TIMESTAMP_END] = data[TIMESTAMP_END];
				objectStorePut("HISTORY_KEY", history);
			}
		}
		else {
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
		str = "Now";
	}
	else if (min < 60){
		str = min.toNumber() + (fullText ? " minute" + (min >= 2 ? "s" : "") : "m");
	}
	else if (min < 60 * 24) {
		var hours = Math.floor(min / 60);
		var mins = min - hours * 60;
		str = hours.toNumber() + (fullText ? " hour" + (hours >= 2 ? "s " : " ") + mins.format("%2d") + " minute" + (mins >= 2 ? "s" : "") : "h" + mins.format("%02d"));
	}
	else {
		var days = Math.floor(min / 60 / 24);
		var hours = Math.floor((min / 60) - days * 24);
		str = days.toNumber() + (fullText ? " day" + (days >= 2 ? "s " : " ") : "d ") + hours.toNumber() + (fullText ? " hour" + (hours >= 2 ? "s" : "") : "h");
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
