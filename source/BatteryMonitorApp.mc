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
const HISTORY_MAX = 3000; // At 5 minutes per interval is over 10 days of data
const INTERVAL_MIN = 5;//temporal event in minutes

//! Object store keys (now they keys are in Storage and are texts, not numbers)
// const HISTORY_KEY = 2;
// const LAST_HISTORY_KEY = 3;
// const COUNT = 1;
// const LAST_VIEWED_DATA = 4;
// const LAST_CHARGED_DATA = 5;
// const STARTED_CHARGING_DATA = 6;
// const UPDATE_DATA = 7; //  This guy is set if we need to upgrade our data structure to the new version without using the history
// const VIEW_RUNNING = 8; // When True, the main view updates the history data so we skip the background process


const COLOR_BAT_OK = Gfx.COLOR_GREEN;
const COLOR_BAT_LOW = Gfx.COLOR_YELLOW;
const COLOR_BAT_CRITICAL = Gfx.COLOR_RED;
const COLOR_PROJECTION = Gfx.COLOR_DK_BLUE;

const SCREEN_DATA_HR = 1;
const SCREEN_DATA_DAY = 2;
const SCREEN_HISTORY = 3;
const SCREEN_PROJECTION = 4;

//! History Array data type
enum{
	TIMESTAMP_START,
	TIMESTAMP_END,
	BATTERY,
	FREEMEMORY
}

var gAbleBackground = false;
var gViewScreen = SCREEN_DATA_HR;

(:background)
class BatteryMonitorApp extends App.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
		// var update = objectStoreGet("UPDATE_DATA", 0);

		// if (update < 2) {
		// 	var history = objectStoreGet("HISTORY_KEY", null);
		// 	if (history instanceof Toybox.Lang.Array) {
		// 		if (history[0][BATTERY] instanceof Toybox.Lang.Float) {
		// 			for (var i = 0; i < history.size(); i++) {
		// 				history[i][BATTERY] = (history[i][BATTERY] * 1000).toNumber();
		// 			}
		// 			objectStorePut("HISTORY_KEY", history);
		// 		}
		// 	}

		// 	history = objectStoreGet("LAST_HISTORY_KEY", null);
		// 	if (history != null) {
		// 		if (history[BATTERY] instanceof Toybox.Lang.Float) {
		// 			history[BATTERY] = (history[BATTERY] * 1000).toNumber();
		// 			objectStorePut("LAST_HISTORY_KEY", history);
		// 		}
		// 	}

		// 	objectStorePut("UPDATE_DATA", 2);
		// }
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    (:glance)
    function getGlanceView() {
    	if (Toybox.System has :ServiceDelegate) {
            gAbleBackground = true;
            Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
        }
        return [ new BatteryMonitorGlanceView() ];
    }

    // Return the initial view of your application here
    function getInitialView() {	
    	//register for temporal events if they are supported
    	if (Toybox.System has :ServiceDelegate) {
    		gAbleBackground = true;
    		Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
    	}
        return [ new BatteryMonitorView() , new BatteryMonitorDelegate() ];
    }
    
    function getServiceDelegate(){
        return [new BatteryMonitorServiceDelegate()];
    }

    function onBackgroundData(data) {
    	//DEBUG*/ logMessage("App/onBackgroundData");
    	//DEBUG*/ logMessage("data received " + data);
		if (data != null) {
			analyzeAndStoreData(data);
        	Ui.requestUpdate();
		}
    }    
}
