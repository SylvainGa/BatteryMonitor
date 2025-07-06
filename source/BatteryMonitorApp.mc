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

//! App constants
const HISTORY_MAX = 1200; // Quad the max screen size should be enough data to keep but could be too much for large screen so max at 1200 (around 32KB)
const INTERVAL_MIN = 5; // temporal event in minutes
const UPDATE_VERSION = 5; // What version our array structures should be at

//! Object store keys (now they keys are in Storage and are texts, not numbers)
// const HISTORY_KEY = 2;
// const LAST_HISTORY_KEY = 3;
// const LAST_VIEWED_DATA = 4;
// const LAST_CHARGED_DATA = 5;
// const STARTED_CHARGING_DATA = 6;
// const UPDATE_DATA = 7; //  This guy is set if we need to upgrade our data structure to the new version without using the history
// const VIEW_RUNNING = 8; // When True, the main view updates the history data so we skip the background process
// const LAST_SLOPE_CALC = 9;
// const LAST_SLOPE_VALUE = 10;

const COLOR_BAT_OK = Gfx.COLOR_GREEN;
const COLOR_BAT_WARNING = Gfx.COLOR_YELLOW;
const COLOR_BAT_LOW = Gfx.COLOR_ORANGE;
const COLOR_BAT_CRITICAL = Gfx.COLOR_RED;
const COLOR_PROJECTION = Gfx.COLOR_DK_BLUE;

const SCREEN_DATA_MAIN = 1;
const SCREEN_DATA_HR = 2;
const SCREEN_DATA_DAY = 3;
const SCREEN_LAST_CHARGE = 4;
const SCREEN_HISTORY = 5;
const SCREEN_PROJECTION = 6;

//! History Array data type
enum {
	TIMESTAMP,
	BATTERY`,
	SOLAR
}
const HISTORY_ELEMENT_SIZE_SOLAR = 3; // Solar watches have three fields of 4 bytes (signed 32 bits) each, TIMESTAMP, BATTERY and SOLAR
const HISTORY_ELEMENT_SIZE = 2; // Non solar watches have two fields of 4 bytes (signed 32 bits) each, TIMESTAMP and BATTERY

(:background)
class BatteryMonitorApp extends App.AppBase {
	var mView;
	var mDelegate;

    function initialize() {
        AppBase.initialize();
    }	

    // onStart() is called on application start up
    function onStart(state) {
		var bgIntervals = 5 * 60; // 5 minutes minimum
		// var history = objectStoreGet("HISTORY_KEY", null);
		// if (history != null) {
		// 	var size = history.size();
		// 	if (size > 288) { // Equivalent to a day at 5 minutes intervals
		// 		bgIntervals = 900; // After a day's worth of data, drop the intervals to 15 minutes intervals to lessen the impact on the system
		// 	}
		// }

    	if (Toybox.System has :ServiceDelegate) {
			//DEBUG*/ logMessage("Will run BG every " + (bgIntervals / 60) + " minutes" );
			Background.registerForTemporalEvent(new Time.Duration(bgIntervals));
		}

		/**** UNCOMMEMT TO UPGRADE ARRAYS STRUCTURES ****/
		// // This update drops the precision of the Battery field from 3 decimal to 1 decimal. 3 was overboard.
		// var update = objectStoreGet("UPDATE_DATA", null);
		// /*DEBUG*/ logMessage("UPDATE_DATA is " + update);
		// if (history != null) {
		// 	if (update == null || update != UPDATE_VERSION) {
		// 		/*DEBUG*/ logMessage("Updating arrays");
		// 		var count = 0;
		// 		if (history instanceof Toybox.Lang.Array) {
		// 			if (history[0][BATTERY] instanceof Toybox.Lang.Number) {
		// 				/*DEBUG*/ logMessage("HISTORY_KEY is the right format to update");
		// 				for (var i = 0; i < history.size(); i++) {
		// 					history[i][BATTERY] = (history[i][BATTERY] / 100).toNumber();
		// 				}
		// 				objectStorePut("HISTORY_KEY", history);
		// 				count++;
		// 			}
		// 		}

		// 		history = objectStoreGet("LAST_HISTORY_KEY", null);
		// 		if (history != null) {
		// 			if (history[BATTERY] instanceof Toybox.Lang.Number) {
		// 				/*DEBUG*/ logMessage("LAST_HISTORY_KEY is the right format to update");
		// 				history[BATTERY] = (history[BATTERY] / 100).toNumber();
		// 				objectStorePut("LAST_HISTORY_KEY", history);
		// 				count++;
		// 			}
		// 		}

		// 		history = objectStoreGet("LAST_VIEWED_DATA", null);
		// 		if (history != null) {
		// 			if (history[BATTERY] instanceof Toybox.Lang.Number) {
		// 				/*DEBUG*/ logMessage("LAST_VIEWED_DATA is the right format to update");
		// 				history[BATTERY] = (history[BATTERY] / 100).toNumber();
		// 				objectStorePut("LAST_VIEWED_DATA", history);
		// 				count++;
		// 			}
		// 		}

		// 		history = objectStoreGet("LAST_CHARGED_DATA", null);
		// 		if (history != null) {
		// 			if (history[BATTERY] instanceof Toybox.Lang.Number) {
		// 				/*DEBUG*/ logMessage("LAST_CHARGED_DATA is the right format to update");
		// 				history[BATTERY] = (history[BATTERY] / 100).toNumber();
		// 				objectStorePut("LAST_CHARGED_DATA", history);
		// 				count++;
		// 			}
		// 		}

		// 		history = objectStoreGet("STARTED_CHARGING_DATA", null);
		// 		if (history != null) {
		// 			if (history[BATTERY] instanceof Toybox.Lang.Number) {
		// 				/*DEBUG*/ logMessage("STARTED_CHARGING_DATA is the right format to update");
		// 				history[BATTERY] = (history[BATTERY] / 100).toNumber();
		// 				objectStorePut("STARTED_CHARGING_DATA", history);
		// 				count++;
		// 			}
		// 		}

		// 		/*DEBUG*/ logMessage("Update to version " + UPDATE_VERSION + " complete" + (count != 5 ? " but with some arrays not being updated." : "."));
		// 		objectStorePut("UPDATE_DATA", UPDATE_VERSION);
		// 		objectStorePut("IGNORE_NEXT_BGDATA", true);
		// 	}
		// }
		// else {
		// 	/*DEBUG*/ logMessage("No history to update");
		// 	objectStorePut("UPDATE_DATA", UPDATE_VERSION);
		// }
		/**** UNCOMMEMT TO UPGRADE ARRAYS STRUCTURES ****/
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    (:glance)
    function getGlanceView() {
		mView = new BatteryMonitorGlanceView();
        return [ mView ];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		mView = new BatteryMonitorView();
		mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceive));
        return [ mView , mDelegate ];
    }
    
    function getServiceDelegate(){
        return [new BatteryMonitorServiceDelegate()];
    }

    function onBackgroundData(data) {
    	//DEBUG*/ logMessage("App/onBackgroundData");
    	/*DEBUG*/ logMessage("onBG (" + (mDelegate == null ? "BG" : "VIEW") + "): " + data);

		if (objectStoreGet("IGNORE_NEXT_BGDATA", false) == true) { // So we skip pending updates that could potentially be in the wrong format after an array redefinition
			objectStorePut("IGNORE_NEXT_BGDATA", false);
			return;
		}

		if (data != null /* && mDelegate == null*/) {
			analyzeAndStoreData(data, data.size());
        	Ui.requestUpdate();
		}
    }    

	function onSettingsChanged() {
		if (mView != null) {
			mView.onSettingsChanged();
		}
	}
}
