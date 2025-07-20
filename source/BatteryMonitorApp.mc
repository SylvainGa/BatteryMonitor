using Toybox.Application as App;
using Toybox.Background;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Complications;
using Toybox.Attention;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Application.Storage;

//! App constants
const HISTORY_MAX = 500; // Quad the max screen size should be enough data to keep but could be too much for large screen so max at 1200 (around 32KB)
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
	public var mHistoryNeedsReload;
	public var mFullHistoryNeedsRefesh;

	// Testing array passing by references
	// public var mArray;
	// public var mArraySize;

    function initialize() {
        AppBase.initialize();
    }	

    // onStart() is called on application start up
    function onStart(state) {
		/*DEBUG*/ logMessage("Start: mHistory " + (mHistory != null ? "has data" : "is null") + " state is " + state);

        if (state != null) {
            if (state.get(:launchedFromComplication) != null) {
                if (Attention has :vibrate) {
                    var vibeData = [ new Attention.VibeProfile(50, 200) ]; // On for 200 ms at 50% duty cycle
                    Attention.vibrate(vibeData);
                }
            }
        }
    }

    function onBackgroundData(data) {
    	//DEBUG*/ logMessage("App/onBackgroundData");
		/*DEBUG*/ logMessage("onBG (" + (mView == null ? "SD)" : (mGlance == null ? "VW)" : "GL)")) + " data: " + data);
    	//DEBUG*/ logMessage("onBG: " + data);

		// Make sure we have the latest data from storage if we're empty, otherwise use what you have
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}
		else {
	    	//DEBUG*/ logMessage("Already have " + mHistorySize);
		}

		if (data != null /* && mDelegate == null*/) {
			var size = data.size();
			$.analyzeAndStoreData(data, size);
		
			// Because onBackgroundData is called BEFORE the getGlanceView/getInitialView, we need to save our data otherwise it will be lost when we read the history in those function
			// if (mHistoryModified == true) {
		    // 	/*DEBUG*/ logMessage("onBG: History changed, saving " + mHistorySize);
			// 	storeHistory(true, mHistory[0 + TIMESTAMP]);
			// }
        	Ui.requestUpdate();
		}
    }    

    // onStop() is called when your application is exiting
    function onStop(state) {
		/*DEBUG*/ logMessage("onStop (" + (mView == null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));

		if (mHistory != null && mHistoryModified == true) {
			/*DEBUG*/ logMessage("History changed, saving " + mHistorySize + " to HISTORY_" + mHistory[0 + TIMESTAMP]);

			storeHistory(true, mHistory[0 + TIMESTAMP]);
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
		/*DEBUG*/ logMessage("getGlanceView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getGlanceView");

		//DEBUG*/ logMessage("Stopping BG process");
		// Terminate the background process as we'll be doing the reading while the glance view is running
		Background.deleteTemporalEvent();

		// Tell the 'Main View' that we launched from Glance
        Storage.setValue("fromGlance", true);

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}

		mView = new BatteryMonitorGlanceView();
		mGlance = mView; // So we know it's specifically a Glance view
        return [mView];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		/*DEBUG*/ logMessage("getInitialView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getInitialView");

		//DEBUG*/ logMessage("Stopping BG process");
		// Terminate the background process as we'll be doing the reading while the main view is running
		Background.deleteTemporalEvent();

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			// /*DEBUG*/ buildFakeHistory();
			// $.objectStorePut("HISTORY", mHistory); // Amnd erase the old data
			// var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
			// if (historyArray != null) {
			// 	for (var i = 0; i < historyArray.size(); i++) {
			// 		$.objectStoreErase("HISTORY_" + historyArray[i]);
			// 	}
			// 	$.objectStoreErase("HISTORY_ARRAY");
			// }

			getLatestHistoryFromStorage();
		}

        if ($.objectStoreGet("fromGlance", false) == true) { // Up/Down buttons work when launched from glance (or if we don't have/need buttons)
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

            /*DEBUG*/ logMessage(("Launching main view"));
			mView = new BatteryMonitorView();
			mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceive));
			return [mView , mDelegate];
        }
        else { // Sucks, but we have to have an extra view so the Up/Down button work in our main view
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

            /*DEBUG*/ logMessage(("Launching no glance view"));
			mView = new NoGlanceView();
			mDelegate = new NoGlanceDelegate();
			return [mView , mDelegate];
        }
    }

    function getServiceDelegate(){
		/*DEBUG*/ logMessage("getServiceDelegate: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getServiceDelegate");
        return [new BatteryMonitorServiceDelegate()];
    }

	function storeHistory(modified, timestamp) {
		if (modified == true) {
			$.objectStorePut("HISTORY_" + mHistory[0 + TIMESTAMP], mHistory); // Store our history using the first timestamp for a key
		}

		var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
		if (historyArray.size() == 0 || historyArray[historyArray.size() - 1] != timestamp) { // If that key isn't in the array of histories, add it
			historyArray.add(timestamp);
			if (historyArray.size() > 5) { // But if we already have 5 history arrays, drop the earliest one
				/*DEBUG*/ logMessage("Too many history arrays, droping HISTORY_" + historyArray[0]);
				$.objectStoreErase("HISTORY_" + historyArray[0]);
				$.objectStoreErase("SLOPES_" + historyArray[0]);
				historyArray.remove(historyArray[0]);
				mHistoryNeedsReload = true;
			}
			$.objectStorePut("HISTORY_ARRAY", historyArray);
		}
		mHistoryModified = false;
	}

    (:glance)
	function getLatestHistoryFromStorage() {
		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		mHistory = null; // Free up memory if we had any set aside
		mHistorySize = 0;

		while (true) {
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
			if (historyArray != null && historyArray.size() > 0) {
				mHistory = $.objectStoreGet("HISTORY_" + historyArray[historyArray.size() - 1], null);
				if (mHistory != null) {
					/*DEBUG*/ getHistorySize(); logMessage("getLatest.. Read " + mHistorySize + " from " + "HISTORY_" + historyArray[historyArray.size() - 1]);
					break;
				 }
				 else { // We had corruption? Drop it and try again
				 	/*DEBUG*/ logMessage("Unable to read from HISTORY_" + historyArray[historyArray.size() - 1] + ". Dropping it");
					$.objectStoreErase("HISTORY_" + historyArray[historyArray.size() - 1]);
					historyArray.remove(historyArray[historyArray.size() - 1]);
					if (historyArray.size() > 0) {
						$.objectStorePut("HISTORY_ARRAY", historyArray);
					}
					else {
						$.objectStoreErase("HISTORY_ARRAY");
						break; // Get out, we're now empty
					}
				}
			}
			else {
				break; // We have nothing, get out of the loop
			}
		}
		
		if (mHistory == null) { // Nothing from our arrays of history, see if we had the old format
			// If we don't have data, see if the old history array is there and if so, convert it to the new format
			var historyArray = [];
			var history = $.objectStoreGet("HISTORY_KEY", null);
			if (history != null) {
				/*DEBUG*/ logMessage("Old HISTORY_KEY format found, dropping it");
				$.objectStoreErase("HISTORY_KEY", null);
			}
		
			history = $.objectStoreGet("HISTORY", null);
			//DEBUG*/ buildFakeHistory(); history = mHistory;
			if (history != null) {
				/*DEBUG*/ logMessage("Converting old history format to new one");
				var i = 0;
				while (i < history.size()) {
					mHistory = null;
					mHistory = new [HISTORY_MAX * elementSize];
					for (var j = 0; i < history.size() && j < HISTORY_MAX * elementSize; i++, j++) {
						mHistory[j] = history[i];
					}

					historyArray.add(mHistory[0 + TIMESTAMP]);
					$.objectStorePut("HISTORY_" + mHistory[0 + TIMESTAMP], mHistory);
					/*DEBUG*/ logMessage("HISTORY_" + mHistory[0 + TIMESTAMP] + " added to store with " + (mHistory.size() / elementSize) + " elements");
				}

				$.objectStorePut("HISTORY_ARRAY", historyArray);
				$.objectStoreErase("HISTORY"); // And erase the old data
			}
		}

		if (mHistory == null) {
			/*DEBUG*/ logMessage("Starting from fresh!");
			mHistory = new [HISTORY_MAX * elementSize];
		}

		getHistorySize();
		mHistoryModified = false;
		mHistoryNeedsReload = true;
		mFullHistoryNeedsRefesh = true;

		//DEBUG*/ for (var i = 0; i < mHistorySize; i++) { if (mHistory[i*3 + BATTERY] >= 2000) { mHistory[i*3 + BATTERY] = (mHistory[i*3 + BATTERY] - 2000) | 0x400; } } //Replace 2000 Activity flag for a bitwise operator so we can tell which activity was running
		//DEBUG*/ Sys.print("["); for (var i = 0; i < mHistorySize; i++) { if (true || mHistory[i*3 + TIMESTAMP] < 1752135321) { Sys.print(mHistory[i*3 + TIMESTAMP] + "," + mHistory[i*3 + BATTERY] + "," + mHistory[i*3 + SOLAR]); if (i < mHistorySize - 1) { Sys.print(","); } } } Sys.println("]");
	}

	function setHistory(history) {
		mHistory = history;
		mHistorySize = 0;
		getHistorySize();
		mHistoryNeedsReload = true;
		mFullHistoryNeedsRefesh = true;

		return [mHistory, mHistorySize];
	}

	function getHistorySize() {
		if (mHistory == null) {
			return 0;
		}

		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		//DEBUG*/ logMessage("(1) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " elementSize is " + elementSize);

		var historySize = mHistory.size();
		if (historySize != HISTORY_MAX * elementSize) {
			/*DEBUG*/ logMessage("mHistory is " + mHistory.size() + "elements instead of " + HISTORY_MAX * elementSize + "! Resizing it");
			var newHistory = new [HISTORY_MAX * elementSize];
			var i = 0;
			for (; i < historySize && i < HISTORY_MAX * elementSize; i++) {
				newHistory[i] = mHistory[i];
			}

			mHistory = newHistory;
			mHistorySize = i / elementSize;
		}

		// If our current postion is null and our previous is ALSO null, start from scratch, otherwise start from our current position to improve performance
		if (mHistorySize == null || mHistorySize >= HISTORY_MAX * elementSize || mHistorySize == 0 || mHistory[(mHistorySize - 1) * elementSize + TIMESTAMP] == null) {
			/*DEBUG*/ logMessage("mHistorySize was " + mHistorySize);
			mHistorySize = 0;
		}

		//DEBUG*/ logMessage("(2) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " elementSize is " + elementSize + " HISTORY_MAX is " + HISTORY_MAX + " TIMESTAMP is " + TIMESTAMP);

		for (; mHistorySize < HISTORY_MAX; mHistorySize++) {
			if (mHistory[mHistorySize * elementSize + TIMESTAMP] == null) {
				break;
			}
		}

		//DEBUG*/ logMessage("(3) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " elementSize is " + elementSize);

		return mHistorySize;
	}

	function getHistoryModified() {
		return mHistoryModified;
	}

	function setHistoryModified(state) {
		mHistoryModified = state;
	}

	function getHistoryNeedsReload() {
		return mHistoryNeedsReload;
	}

	function setHistoryNeedsReload(state) {
		mHistoryNeedsReload = state;
	}

	function getFullHistoryNeedsRefesh() {
		return mFullHistoryNeedsRefesh;
	}

	function setFullHistoryNeedsRefesh(state) {
		mFullHistoryNeedsRefesh = state;
	}


	(:debug)
	function buildFakeHistory() {
	    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
		mHistory = [now - 16000, 800, 0, now - 13000, 790, 0, now - 11200, 800, 0, now - 1900, 875, 0, now - 1600, 770, 0, now - 300, 750, 0, now - 1200, 740, 0, now - 1100, 730, 0, now, 720, 0];
		return;
		// var span = 60 * 2460; // 1 day 16 hours
		// var start = now - span;
		// var size = span / (5 * 60); // One entry per 5 minutes
		// var batInitialLevel = 80.0;
		// var batLastLevel = 5.0;
		// var batDrain = (batInitialLevel - batLastLevel) / size;
		// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
		// mHistory = new [size * elementSize];
		// for (var i = 0; i < size; i++) {
		// 	mHistory[i * elementSize + TIMESTAMP] = start + i * 5 * 60;
		// 	mHistory[i * elementSize + BATTERY] = ((batInitialLevel - batDrain * i) * 10).toNumber();
		// 	if (isSolar) {
		// 		mHistory[i * elementSize + SOLAR] = Math.rand() % 100;
		// 	}
		// }
		// mHistorySize = size;
	}

	(:release)
	function buildFakeHistory() {
	}
}
