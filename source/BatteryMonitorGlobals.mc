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
function stripTrailingZeros(value) {
    if (value instanceof Lang.String) {
		if (value.find(".") != null) { // Only mathers if we contain a decimal
			var carray = value.toCharArray();
			var i = carray.size() - 1;
			for (; i > 0; i--) {
				if (carray[i].equals('.')) { // If we reached the '.', we'll skip it too and stop so we don't drop zeros before '.'
					i--;
					break;
				}
				if (carray[i].equals('0')) { // Trailing zero? Keep going
					continue;
				}

				break; // Not one of the above, so that's where we stop
			}

			return value.substring(0, i + 1); // Return the text before we stopped
		}
	}
	return value;
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
	var clockTime = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
	var dateStr = clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
	Sys.println(dateStr + " : " + message);
}
