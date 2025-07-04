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
const SCREEN_HISTORY = 4;
const SCREEN_PROJECTION = 5;

//! History Array data type
enum{
	TIMESTAMP,
	BATTERY`,
	SOLAR
}

var gViewScreen = SCREEN_DATA_MAIN;

(:background)
class BatteryMonitorApp extends App.AppBase {
	var mView;
	var mDelegate;

    function initialize() {
        AppBase.initialize();
    }	

    // onStart() is called on application start up
    function onStart(state) {
		/**** UNCOMMEMT TO UPGRADE ARRAYS STRUCTURES ****/
		// This update drops the precision of the Battery field from 3 decimal to 1 decimal. 3 was overboard.
		var update = objectStoreGet("UPDATE_DATA", null);
		/*DEBUG*/ logMessage("UPDATE_DATA is " + update);
		if (update == null || update != UPDATE_VERSION) {
			/*DEBUG*/ logMessage("Updating arrays");
			var count = 0;
			var history = objectStoreGet("HISTORY_KEY", null);
			if (history instanceof Toybox.Lang.Array) {
				if (history[0][BATTERY] instanceof Toybox.Lang.Number) {
					/*DEBUG*/ logMessage("HISTORY_KEY is the right format to update");
					for (var i = 0; i < history.size(); i++) {
						history[i][BATTERY] = (history[i][BATTERY] / 100).toNumber();
					}
					objectStorePut("HISTORY_KEY", history);
					count++;
				}
			}

			history = objectStoreGet("LAST_HISTORY_KEY", null);
			if (history != null) {
				if (history[BATTERY] instanceof Toybox.Lang.Number) {
					/*DEBUG*/ logMessage("LAST_HISTORY_KEY is the right format to update");
					history[BATTERY] = (history[BATTERY] / 100).toNumber();
					objectStorePut("LAST_HISTORY_KEY", history);
					count++;
				}
			}

			history = objectStoreGet("LAST_VIEWED_DATA", null);
			if (history != null) {
				if (history[BATTERY] instanceof Toybox.Lang.Number) {
					/*DEBUG*/ logMessage("LAST_VIEWED_DATA is the right format to update");
					history[BATTERY] = (history[BATTERY] / 100).toNumber();
					objectStorePut("LAST_VIEWED_DATA", history);
					count++;
				}
			}

			history = objectStoreGet("LAST_CHARGED_DATA", null);
			if (history != null) {
				if (history[BATTERY] instanceof Toybox.Lang.Number) {
					/*DEBUG*/ logMessage("LAST_CHARGED_DATA is the right format to update");
					history[BATTERY] = (history[BATTERY] / 100).toNumber();
					objectStorePut("LAST_CHARGED_DATA", history);
					count++;
				}
			}

			history = objectStoreGet("STARTED_CHARGING_DATA", null);
			if (history != null) {
				if (history[BATTERY] instanceof Toybox.Lang.Number) {
					/*DEBUG*/ logMessage("STARTED_CHARGING_DATA is the right format to update");
					history[BATTERY] = (history[BATTERY] / 100).toNumber();
					objectStorePut("STARTED_CHARGING_DATA", history);
					count++;
				}
			}

			/*DEBUG*/ logMessage("Update to version " + UPDATE_VERSION + " complete" + (count != 5 ? " but with some arrays not being updated." : "."));
			objectStorePut("UPDATE_DATA", UPDATE_VERSION);
		}
		/**** UNCOMMEMT TO UPGRADE ARRAYS STRUCTURES ****/
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    (:glance)
    function getGlanceView() {
    	if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
        }

		mView = new BatteryMonitorGlanceView();
        return [ mView ];
    }

    // Return the initial view of your application here
    function getInitialView() {	
    	//register for temporal events if they are supported
    	if (Toybox.System has :ServiceDelegate) {
    		Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
    	}

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
		if (data != null /* && mDelegate == null*/) {
			//DEBUG*/ data = [[1751313777, 35381],[1751314002, 35381],[1751314270, 35883],[1751314302, 35805],[1751314902, 35484],[1751315007, 35455],[1751315047, 35381]];
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
