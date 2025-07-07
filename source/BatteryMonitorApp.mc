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
	var mGlance;
	var mDelegate;
	public var mHistory;
	public var mHistorySize;
	public var mHistoryModified;

	// Testing array passing by references
	// public var mArray;
	// public var mArraySize;

    function initialize() {
        AppBase.initialize();
    }	

    // onStart() is called on application start up
    function onStart(state) {
		/*DEBUG*/ logMessage("Start");
        // Testing array passing by references
		// mArray = [10, 20, 30];
		// mArraySize = mArray.size();
		// Sys.println("App array is " + mArray + " size is " + mArraySize);

		//DEBUG*/ logMessage("Will run BG every " + (bgIntervals / 60) + " minutes" );
		Background.registerForTemporalEvent(new Time.Duration(300));
    }

    function onBackgroundData(data) {
    	//DEBUG*/ logMessage("App/onBackgroundData");
    	/*DEBUG*/ logMessage("onBG " + data);

		// Make sure we have the latest data from storage if we're empty, otherwise use what you have
		if (mHistory == null) {
			getHistoryFromStorage();
		}
		else {
	    	/*DEBUG*/ logMessage("Already have " + mHistorySize);
		}

		// if ($.objectStoreGet("IGNORE_NEXT_BGDATA", false) == true) { // So we skip pending updates that could potentially be in the wrong format after an array redefinition
		// 	$.objectStorePut("IGNORE_NEXT_BGDATA", false);
		// 	return;
		// }

		if (data != null /* && mDelegate == null*/) {
			var size = data.size();
			$.analyzeAndStoreData(data, data.size());

			// If we had more than one data waiting to be read, to be safe, save the HISTORY right now in case we crash later on
			if (size > 1 && mHistoryModified == true) {
				$.objectStorePut("HISTORY", mHistory);
		    	/*DEBUG*/ logMessage("History changed, saving " + mHistorySize);
				mHistoryModified = false;
			}
        	Ui.requestUpdate();
		}
    }    

    // onStop() is called when your application is exiting
    function onStop(state) {
		/*DEBUG*/ logMessage("Stop (" + (mView == null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));
		if (mHistory != null && mHistoryModified == true) {
			$.objectStorePut("HISTORY", mHistory);
			/*DEBUG*/ logMessage("History changed, saving " + mHistorySize);
			mHistoryModified = false;
		}

		if (mView != null) {
			/*DEBUG*/ logMessage("Restarting BG process");
			Background.registerForTemporalEvent(new Time.Duration(300));
		}
    }

	function onSettingsChanged() {
		if (mView != null) {
			mView.onSettingsChanged();
		}
	}

    (:glance)
    function getGlanceView() {
		/*DEBUG*/ logMessage("getGlanceView");

		/*DEBUG*/ logMessage("Stopping BG process");
		// Terminate the background process as we'll be doing the reading while the glance view is running
		Background.deleteTemporalEvent();

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getHistoryFromStorage();
		}

		mView = new BatteryMonitorGlanceView();
		mGlance = mView; // So we know it's specifically a Glance view
        return [ mView ];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		/*DEBUG*/ logMessage("getInitialView");

		/*DEBUG*/ logMessage("Stopping BG process");
		// Terminate the background process as we'll be doing the reading while the main view is running
		Background.deleteTemporalEvent();

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getHistoryFromStorage();
		}

		mView = new BatteryMonitorView();
		mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceive));
        return [ mView , mDelegate ];
    }
    
    function getServiceDelegate(){
		/*DEBUG*/ logMessage("getServiceDelegate");
        return [new BatteryMonitorServiceDelegate()];
    }

	function getHistoryFromStorage() {
		mHistory = $.objectStoreGet("HISTORY", null);
		if (mHistory == null) { // To prefill the history with the data we currently have in our previous history array
			var mHistory = $.objectStoreGet("HISTORY_KEY", null);
			if (mHistory != null) {
		    	/*DEBUG*/ logMessage("Reading from HISTORY_KEY");
				$.objectStorePut("HISTORY", mHistory);
			}
		}

		getHistorySize();

		mHistoryModified = false;

		/*DEBUG*/ logMessage("getHistoryFromStorage Read " + mHistorySize);
	}

	function setHistory(history) {
		mHistory = history;
		getHistorySize();

		return [mHistory, mHistorySize];
	}

	function getHistorySize() {
		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		mHistorySize = mHistory != null ? mHistory.size() / elementSize : 0;

		return mHistorySize;
	}

	function getHistoryModified() {
		return mHistoryModified;
	}

	function setHistoryModified(state) {
		mHistoryModified = state;
	}

	// Testing array passing by references
	// function setArray(newArray) {
	// 	mArray = newArray;
	// 	mArraySize = mArray.size();

	// 	return [mArray, mArraySize];
	// }

	// function getArraySize() {
	// 	mArraySize = mArray.size();
	// 	return mArraySize;
	// }
}
