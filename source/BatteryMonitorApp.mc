using Toybox.Application as App;
using Toybox.Background;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Complications;
using Toybox.Attention;
using Toybox.Time;
using Toybox.Timer;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Application.Storage;

//! App constants
const HISTORY_MAX = 500; // Quad the max screen size should be enough data to keep but could be too much for large screen so max at 1200 (around 32KB)

//! Object store keys (now they keys are in Storage and are texts, not numbers)
// const HISTORY_KEY = 2;
// const LAST_HISTORY_KEY = 3;
// const LAST_VIEWED_DATA = 4;
// const LAST_CHARGED_DATA = 5;
// const STARTED_CHARGING_DATA = 6;
// const MARKER_DATA = 7;

const COLOR_BAT_OK = Gfx.COLOR_GREEN;
const COLOR_BAT_WARNING = Gfx.COLOR_YELLOW;
const COLOR_BAT_LOW = Gfx.COLOR_ORANGE;
const COLOR_BAT_CRITICAL = Gfx.COLOR_RED;
const COLOR_PROJECTION = Gfx.COLOR_DK_BLUE;

const SCREEN_DATA_MAIN = 1;
const SCREEN_DATA_HR = 2;
const SCREEN_DATA_DAY = 3;
const SCREEN_LAST_CHARGE = 4;
const SCREEN_MARKER = 5;
const SCREEN_HISTORY = 6;
const SCREEN_PROJECTION = 7;
const MAX_SCREENS = 7;

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
	var mService;
	public var mHistory;
	public var mHistorySize;
	public var mHistoryModified; // The current history array has been modified and will need to be saved when we exit
	public var mHistoryNeedsReload; // A reload is when the full history needs to be rebuilt from scratch since the history arrays have changed
	public var mFullHistoryNeedsRefesh; // A refresh is when only the current history array needs to be readded to the full history

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

		startBackgroundService(false);
    }

    function onBackgroundData(data) {
    	//DEBUG*/ logMessage("App/onBackgroundData");
		/*DEBUG*/ logMessage("onBGData (" + (mService != null ? "SD)" : "VW or GL)") + " data: " + data);
    	//DEBUG*/ logMessage("onBG: " + data);

		// Make sure we have the latest data from storage if we're empty, otherwise use what you have
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}
		else {
	    	/*DEBUG*/ logMessage("Already have " + mHistorySize);
		}

		if (data != null /* && mDelegate == null*/) {
			var size = data.size();
			if ($.analyzeAndStoreData(data, size, false) > 1) {
				/*DEBUG*/ logMessage("Saving history");
				$.objectStorePut("HISTORY_" + mHistory[0 + TIMESTAMP], mHistory);
				mHistoryModified = false;
			}
		
        	Ui.requestUpdate();
		}
    }    

    // onStop() is called when your application is exiting
    function onStop(state) {
		/*DEBUG*/ logMessage("onStop (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));

		// Was in onHide
		if (mService == null && mGlance == null) { // This is JUST for the main view process
			var lastData = $.getData();
			$.analyzeAndStoreData([lastData], 1, false);
			$.objectStorePut("LAST_VIEWED_DATA", lastData);
		}

		// If we have unsaved data, now it's the time to save them
		if (mHistory != null && mHistoryModified == true) {
			/*DEBUG*/ logMessage("History changed, saving " + mHistorySize + " to HISTORY_" + mHistory[0 + TIMESTAMP]);

			storeHistory(true, mHistory[0 + TIMESTAMP]);
		}
    }

    // onAppInstall() is called when your application is installed
    function onAppInstall() {
		/*DEBUG*/ logMessage("onAppInstall (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));
		startBackgroundService(false);
    }

    // onAppUpdate() is called when your application is Updated
    function onAppUpdate() {
		/*DEBUG*/ logMessage("onAppUpdate (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));
		startBackgroundService(false);
	}

	function onSettingsChanged() {
		if (mView != null) {
			mView.onSettingsChanged();
		}

		startBackgroundService(true);
	}

	// Start the background process if it hasn't yet
	function startBackgroundService(redo) {
		var regTime = Background.getTemporalEventRegisteredTime();
		if ( regTime == null || redo == true) {
			/*DEBUG*/ logMessage("Starting BG process");
			var bgInterval = 5;
			try {
				bgInterval = Properties.getValue("BGInterval");
			}
			catch (e) {
				bgInterval = 5;
			}

			if (bgInterval != 0) {
				if (bgInterval < 5) {
					bgInterval = 5;
				}
				bgInterval *= 60;

				Background.registerForTemporalEvent(new Time.Duration(bgInterval));
			}
		}
		else {
			/*DEBUG*/ logMessage("Next BG " + (regTime.value() / 60) + " min");
		}
	}

	(:can_glance)
    function getGlanceView() {
		/*DEBUG*/ logMessage("getGlanceView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getGlanceView");

		// Tell the 'Main View' that we launched from Glance
        Storage.setValue("fromGlance", true);

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}

		// Run the initial slope calc here as it seems to not time out, unlike the view code
		$.initDownSlope();

		mGlance = new BatteryMonitorGlanceView();
		mView = mGlance; // So onSettingsChanged can call the view or glance onSettingsChanged code without needing to check for both
        return [mGlance];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		/*DEBUG*/ logMessage("getInitialView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getInitialView");

		//DEBUG*/ $.dumpHistory(0); //return;

		//DEBUG*/ logMessage("Building fake history"); buildFakeHistory();
		//DEBUG*/ logMessage("Building copied history"); $.buildCopiedHistory(); logMessage("History built from a copy"); return;

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}

		// Run the initial slope calc here as it seems to not time out, unlike the view code
		$.initDownSlope();

		var useBuiltinPageIndicator = true;
		try {
			useBuiltinPageIndicator = Properties.getValue("BuiltinPageIndicator");
		}
		catch (e) {
			useBuiltinPageIndicator = true;
		}

	    if ($.objectStoreGet("fromGlance", false) == true) { // Up/Down buttons work when launched from glance (or if we don't have/need buttons)
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

			if (self has :canViewLoop && WatchUi has :ViewLoop && useBuiltinPageIndicator) {
				var factory = new PageIndicatorFactory();
				var viewLoop = new WatchUi.ViewLoop(factory, {:page => mView.getPanelSize() - 1, :wrap => true/*, :color => Graphics.COLOR_BLACK */});
				return [viewLoop, new PageIndicatorDelegate(viewLoop)];
			} else {
				mView = new BatteryMonitorView(false);
				mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceive), false);
				return [mView , mDelegate];
			}
        }
        else { // Sucks, but we have to have an extra view so the Up/Down button work in our main view
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

			if (/*self has :canViewLoop &&*/ WatchUi has :ViewLoop && useBuiltinPageIndicator) {
				var factory = new PageIndicatorFactory();
				var viewLoop = new WatchUi.ViewLoop(factory, {:page => mView.getPanelSize() - 1, :wrap => true /*, :color => Graphics.COLOR_BLACK */});
				return [viewLoop, new PageIndicatorDelegate(viewLoop)];
			} else {
				/*DEBUG*/ logMessage(("Launching no glance view"));
				mView = new NoGlanceView();
				mDelegate = new NoGlanceDelegate();
				return [mView , mDelegate];
			}
        }
    }

    function getServiceDelegate(){
		/*DEBUG*/ logMessage("getServiceDelegate: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getServiceDelegate");
		mService = new BatteryMonitorServiceDelegate();
        return [mService];
    }

	function getLatestHistoryFromStorage() {
		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		mHistory = null; // Free up memory if we had any set aside
		mHistorySize = 0;

		while (true) {
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
			if (historyArray != null && historyArray.size() > 0) {
				shrinkArraysIfNeeded(historyArray);

				mHistory = $.objectStoreGet("HISTORY_" + historyArray[historyArray.size() - 1], null);
				if (mHistory != null && mHistory.size() == HISTORY_MAX * elementSize) {
					/*DEBUG*/ getHistorySize(); logMessage("getLatest.. Read " + mHistorySize + " from " + "HISTORY_" + historyArray[historyArray.size() - 1]);
					//DEBUG*/ Sys.println(historyArray); var start = mHistory[0 + TIMESTAMP]; Sys.println(start); Sys.print("["); for (var i = 0; i < mHistorySize; i++) { Sys.print(mHistory[i*3 + TIMESTAMP] - start + "," + mHistory[i*3 + BATTERY] + "," + mHistory[i*3 + SOLAR]); if (i < mHistorySize - 1) { Sys.print(","); } } Sys.println("];");
					break;
				 }
				 else { // We had corruption? Drop it and try again
					// Remove this converstion from 3 elements to 2
					// if (mHistory.size() == HISTORY_MAX * 3 && isSolar == false) {
					// 	for (var index = 0; index < historyArray.size(); index++) {
					// 		var history = $.objectStoreGet("HISTORY_" + historyArray[index], null);
					// 		mHistory = new [HISTORY_MAX * elementSize];
					// 		for (var i = 0; i < HISTORY_MAX; i++) {
					// 			mHistory[i * elementSize + TIMESTAMP] = history[i * 3 + TIMESTAMP];
					// 			mHistory[i * elementSize + BATTERY] = history[i * 3 + BATTERY];
					// 		}
					// 		$.objectStorePut("HISTORY_" + historyArray[index], mHistory);
					// 	}
					// 	break; // Now get out as our arrays are now all converted and mHistory has the latest one
					// }
				 	/*DEBUG*/ if (mHistory == null) { logMessage("Unable to read from HISTORY_" + historyArray[historyArray.size() - 1] + ". Dropping it"); } else { logMessage("HISTORY_" + historyArray[historyArray.size() - 1] + "is too short at " + mHistory.size()); }
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
	}

	function storeHistory(modified, timestamp) {
		if (modified == true) {
			$.objectStorePut("HISTORY_" + mHistory[0 + TIMESTAMP], mHistory); // Store our history using the first timestamp for a key
		}

		var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
		if (historyArray.size() == 0 || historyArray[historyArray.size() - 1] != timestamp) { // If that key isn't in the array of histories, add it
			historyArray.add(timestamp);
			$.objectStorePut("HISTORY_ARRAY", historyArray);
			shrinkArraysIfNeeded(historyArray);
		}
		mHistoryModified = false;
	}

	function shrinkArraysIfNeeded(historyArray) {
		var maxArrays = 5;
		try {
			maxArrays = Properties.getValue("MaxArrays");
		} catch (e) {
			maxArrays = 5;
		}

		var handlingFullArray = 0;
		try {
			handlingFullArray = Properties.getValue("HowHandleFullArray");
		} catch (e) {
			handlingFullArray = 0;
		}

		if (historyArray.size() > maxArrays) { // But if we already have the max history arrays
			if (handlingFullArray == 0) { // drop the earliest one
				/*DEBUG*/ logMessage("Too many history arrays, droping HISTORY_" + historyArray[0]);
				$.objectStoreErase("HISTORY_" + historyArray[0]);
				$.objectStoreErase("SLOPES_" + historyArray[0]);
				historyArray.remove(historyArray[0]);
				$.objectStorePut("HISTORY_ARRAY", historyArray);
				mHistoryNeedsReload = true;
			}
			else { // Average earliest one with the one before (but do that in its own timer thread and yes, we'll have an extra array until this merge is completed)
				/*DEBUG*/ logMessage("Too many history arrays, spawning averageHistoryTimer in 100 msec");
				var timer = new Timer.Timer();
				timer.start(method(:averageHistoryTimer), 100, false);
			}
		}
	}

	function averageHistoryTimer() {
		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
		if (historyArray.size() > 1) { // Can't average if we have less than two arrays...
			/*DEBUG*/ logMessage("Too many history arrays, averaging HISTORY_" + historyArray[0] + " and HISTORY_" + historyArray[1] + " into HISTORY_" + historyArray[0]);

			var destHistory = $.objectStoreGet("HISTORY_" + historyArray[0], null); // First the first pass, source and destination is the same as we're shrinking by two
			if (destHistory != null && destHistory.size() == HISTORY_MAX * elementSize) { // Make sure both arrays are fine
				for (var i = 0; i < HISTORY_MAX; i += 2) {
					var destIndex = i / 2 * elementSize;
					var srcIndex = i * elementSize;
					var bat1 = destHistory[srcIndex + BATTERY];
					var bat2 = destHistory[srcIndex + elementSize + BATTERY]; // (same as (i + 1) * elementSize) but without the penalty of a multiplication)
					var batMarkers = (bat1 & 0xF000) | (bat2 & 0xF000);
					destHistory[destIndex + TIMESTAMP] = destHistory[srcIndex + TIMESTAMP]; // We keep the timestamp of the earliest data
					destHistory[destIndex + BATTERY] = (($.stripMarkers(bat1) + $.stripMarkers(bat2)) / 2) | batMarkers; // And average the batteru
					if (isSolar) {
						destHistory[destIndex + SOLAR] = (destHistory[srcIndex + SOLAR] + destHistory[srcIndex + elementSize + SOLAR] / 2); // and the solar, if available
					}
				}
			}
			else { // Something is wrong, delete it and remove it from our history array
				/*DEBUG*/ logMessage("HISTORY_" + historyArray[0] + " is only " + destHistory.size() + " instead of " + (HISTORY_MAX * elementSize) + ". Dropping it");
				$.objectStoreErase("HISTORY_" + historyArray[0]);
				$.objectStoreErase("SLOPES_" + historyArray[0]);
				historyArray.remove(historyArray[0]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				$.objectStorePut("HISTORY_ARRAY", historyArray);
				return; // We simply return since we cleared up space to accomodate a new history array
			}

			var srcHistory = $.objectStoreGet("HISTORY_" + historyArray[1], null);
			if (srcHistory != null && srcHistory.size() == HISTORY_MAX * elementSize) { // Make sure both arrays are fine
				for (var i = 0; i < HISTORY_MAX; i += 2) {
					var destIndex = ((HISTORY_MAX + i) / 2) * elementSize;
					var srcIndex = i * elementSize;
					var bat1 = srcHistory[srcIndex + BATTERY];
					var bat2 = srcHistory[srcIndex + elementSize + BATTERY];
					var batMarkers = (bat1 & 0xF000) | (bat2 & 0xF000);
					destHistory[destIndex + TIMESTAMP] = srcHistory[srcIndex + TIMESTAMP]; // We keep the timestamp of the earliest data
					destHistory[destIndex + BATTERY] = (($.stripMarkers(bat1) + $.stripMarkers(bat2)) / 2) | batMarkers;
					if (isSolar) {
						destHistory[destIndex + SOLAR] = (srcHistory[srcIndex + SOLAR] + srcHistory[srcIndex + elementSize + SOLAR]) / 2;
					}
				}

				$.objectStorePut("HISTORY_" + historyArray[0], destHistory);

				// Now add the slopes
				var slopes0 = $.objectStoreGet("SLOPES_" + historyArray[0], []);
				var slopes1 = $.objectStoreGet("SLOPES_" + historyArray[1], []);
				if (slopes0.size() != 0 && slopes1.size() != 0) {
					slopes0[0].addAll(slopes1[0]);
					for (var i = 0; i < slopes0[0].size() - 1 && slopes0[0].size() > 10 ; i++) { // Average the earliest slopes until we have have a max of 10 slopes (size is going down by one because of the .remove within)
						slopes0[0][i] = (slopes0[0][i] + slopes0[0][i + 1]) / 2; // Average the two adjacent slopes
						slopes0[0].remove(slopes0[0][i + 1]); // And delete the second one now that it's averaged into the first one
					}
					$.objectStorePut("SLOPES_" + historyArray[0], slopes0);
				}

				// Now clean up
				$.objectStoreErase("HISTORY_" + historyArray[1]);
				$.objectStoreErase("SLOPES_" + historyArray[1]);
				historyArray.remove(historyArray[1]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				/*DEBUG*/ logMessage("HISTORY_ARRAY now has " + historyArray);
				$.objectStorePut("HISTORY_ARRAY", historyArray);

			}
			else { // Something is wrong, delete it and remove it from our history array
				/*DEBUG*/ logMessage("HISTORY_" + historyArray[1] + " is only " + srcHistory.size() + " instead of " + (HISTORY_MAX * elementSize) + ". Dropping it");
				$.objectStoreErase("HISTORY_" + historyArray[1]);
				$.objectStoreErase("SLOPES_" + historyArray[1]);
				historyArray.remove(historyArray[1]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				$.objectStorePut("HISTORY_ARRAY", historyArray);

				return; // We simply return since we cleared up space to accomodate a new history array
			}
		}
		else {
			/*DEBUG*/ logMessage("Can't average, only " + historyArray.size() + " history arrays. Need at least 2!");
		}
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
			mHistorySize = 0;
			return mHistorySize;
		}

		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		//DEBUG*/ logMessage("(1) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " elementSize is " + elementSize);

		var historySize = mHistory.size();
		if (historySize != HISTORY_MAX * elementSize) {
			/*DEBUG*/ logMessage("mHistory is " + mHistory.size() + "elements instead of " + HISTORY_MAX * elementSize + "! Resizing it");
			var newHistory = new [HISTORY_MAX * elementSize];
			var i;
			for (i = 0; i < historySize && i < HISTORY_MAX * elementSize; i++) {
				newHistory[i] = mHistory[i];
			}

			mHistory = newHistory;
			mHistorySize = i / elementSize;

			return mHistorySize;
		}

		// Sanity check. If our previous position (mHistorySize - 1) is null, start from scratch, otherwise start from our current position to improve performance
		if (mHistorySize == null || mHistorySize > HISTORY_MAX || (mHistorySize > 0 && mHistory[(mHistorySize - 1) * elementSize + TIMESTAMP] == null)) {
			/*DEBUG*/ if (mHistorySize != 0) { logMessage("mHistorySize was " + mHistorySize); }
			mHistorySize = 0;
		}

		mHistorySize = $.findPositionInArray(mHistory, mHistorySize, elementSize);

		return mHistorySize;

		// for (; mHistorySize < HISTORY_MAX; mHistorySize++) {
		// 	if (mHistory[mHistorySize * elementSize + TIMESTAMP] == null) {
		// 		break;
		// 	}
		// }
		//DEBUG*/ logMessage("(3) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " elementSize is " + elementSize);

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
		// var start = 1753641833;
		// var history = [0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,-300,883,0,0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,18904,772,0,18968,771,0,19028,769,0,19204,768,0,19335,767,0,19503,766,0,19803,760,0,20103,748,0,20357,738,0,20403,737,0,20703,733,0,21003,732,0,21603,731,0,21787,730,0,21800,8922,0,21904,4823,0,22204,4819,0,22503,4815,0,22803,4811,0,23104,4808,0,23404,4804,0,23494,704,0,23500,8896,0,23572,702,0,23704,700,0,24004,693,0,24304,688,0,24904,687,0,25504,686,0,25804,685,0,26704,684,0,26999,682,0,27081,681,0,27305,680,0,27905,679,0,28505,678,0,28806,677,0,28990,676,0,29023,8868,0,29105,675,0,29706,674,0,30305,673,0,30605,672,0,30905,671,0,31205,670,0,31805,669,0,32105,668,0,32705,667,0,33005,666,0,33305,665,0,33606,664,0,33906,663,0,34207,662,0,34807,661,0,35107,660,0,35706,659,0,36007,658,0,36606,657,0,36906,656,0,37206,655,0,37807,654,0,38106,653,0,38706,652,0,39307,651,0,39606,650,0,40206,649,0,40806,648,0,41106,647,0,41706,646,0,42307,645,0,42606,644,0,43207,643,0,43506,642,0,44106,641,0,44706,640,0,45006,639,0,45606,638,0,46206,637,0,46506,636,0,47106,635,0,47707,634,0,48007,633,0,48606,632,0,49506,631,0,50106,630,0,50706,629,0,51307,628,0,51907,627,0,52806,626,0,53407,625,0,54006,624,0,54606,623,0,55506,622,0,56406,621,0,57006,620,0,57606,619,0,58507,618,0,59106,617,0,60007,616,0,60906,615,0,60965,8807,0,61023,614,0,61088,613,0,61148,611,0,61206,609,0,61268,607,0,61328,606,0,61388,605,0,61407,604,0,61506,4698,0,61806,601,0,62106,600,0,63307,599,0,63907,598,0,66006,594,0,66306,588,0,66521,587,0,66583,586,0,66585,585,0,66907,579,0,66936,578,0,66997,577,0,67117,576,0,67177,575,0,67297,574,0,67357,573,0,67477,572,0,67537,571,0,67657,570,0,67717,569,0,67806,568,0,67897,567,0,68017,566,0,68107,565,0,68586,564,0,68600,8756,0,68664,563,0,68724,562,0,68784,561,0,68904,560,0,68964,559,0,68975,8751,0,69307,558,0,69607,4645,14,69907,4639,8,70208,4633,5,70517,4628,14,70816,4622,19,71117,4615,15,71416,4611,43,71716,4606,16,72016,500,0,72316,494,0,72617,493,0,73517,492,0,74116,490,0,74716,489,0,75316,488,0,75616,487,0,76517,486,0,76816,485,0,77716,484,0,78617,482,0,78916,481,0,79216,480,0,79517,479,0,79816,478,0,120916,215,0,120977,213,0,121227,211,0,121826,210,0,122126,209,0,122726,208,0,123026,207,0,123328,205,0,123927,204,0,124228,203,0,124529,202,0,125129,201,0,125429,200,0,126029,199,0,126329,198,0,126929,197,0,127229,196,0,127529,195,0,127829,194,0,128129,193,0,128730,192,0,129030,191,0,129330,190,0,129930,189,0,130231,188,0,130530,187,0,131131,186,0,131431,185,0,132031,184,0,132331,183,0,132932,182,0,133232,181,0,133832,180,0,134132,179,0,134732,178,0,135033,177,0,135633,176,0,135933,175,0,136532,174,0,136833,173,0,137433,172,0,138032,171,0,138332,170,0,138632,169,0,139232,168,0,139532,167,0,140133,166,0,140432,165,0,140732,164,0,141032,163,0,141632,162,0,141932,161,0,142532,160,0,143132,159,0,143432,158,0,143733,157,0,144333,156,0,144632,155,0,145233,154,0,145832,153,0,146132,152,0,146432,150,0,146494,149,0,146554,147,0,146614,145,0,146674,143,0,146732,141,0,146794,140,0,146854,139,0,146914,137,0,146974,135,0,147032,133,0,147094,131,0,147154,130,0,147214,128,0,147274,126,0,147332,124,0,147394,122,0,147454,120,0,147514,119,0,147574,117,0,147632,115,0,147694,113,0,147754,111,0,147814,109,0,147874,107,0,147932,105,0,147994,104,0,148054,102,0,148114,100,0,148174,98,0,148232,97,0,148264,96,0,148287,95,0,148311,94,0,148532,104,0,148832,149,0,149132,194,0,149432,239,0,149732,285,0,150032,330,0,150333,376,0,150633,421,0,150933,467,0,151233,512,0,151533,4637,3,151724,4632,29,151810,4630,30,151833,4629,7,151876,4628,10,152133,4624,18,152433,4620,21,152753,4614,14,152868,514,0,152929,512,0,153053,510,0,153369,509,0,153669,507,0,153969,511,0,154269,556,0,154569,602,0,154869,647,0,155169,692,0,155469,735,0,155769,775,3,155970,774,0,156030,773,0,156056,772,0,156088,771,0,156369,765,0,156669,761,0,157570,760,0,157870,759,0,158770,758,0,159671,757,0,159970,756,0,160570,755,0,160870,754,0,161170,753,0,162070,752,0,162670,751,0,163870,750,0,164170,749,0,164770,748,0,165071,747,0,165370,746,78,166570,745,0,166703,744,0,166763,743,0,167470,742,0,168371,741,0,169270,740,0,169372,739,0,169871,738,0,170170,737,0,170770,736,60,171670,735,17,172571,734,8,173471,733,8,174372,732,0,174972,731,0,175572,730,0,175872,729,0,176173,728,0,176772,727,0,177372,726,0,178574,725,0,179174,724,0,179774,723,0,180674,722,0,181274,721,0,182174,720,0,183074,719,0,183674,718,0,184274,717,0,185474,716,0,185867,715,0,185948,714,0,186976,728,0,187275,726,4,187875,724,1,187985,723,0,190667,717,0,190727,715,0,201992,607,0,202592,606,0,203193,605,0,203792,604,0,204392,603,0,204993,602,0,205892,601,0,206492,600,0,206793,599,0,207393,598,0,207692,597,0,208592,596,0,211597,896,0,211682,894,0,211742,892,0];
		// mHistory = new [HISTORY_MAX * 3];
		// for (var i = 0; i < history.size(); i += 3) {
		// 	mHistory[i] = history[i] + start;
		// 	mHistory[i+1] = history[i+1];
		// 	mHistory[i+2] = history[i+2];
		// }
		// mHistorySize = history.size() / 3;

		// logMessage("Building fake history");
	    // var now = Time.now().value(); //in seconds from UNIX epoch in UTC
		// var span = 60 * 2460; // 1 day 16 hours
		// var start = now - span;
		// var size = span / (5 * 60); // One entry per 5 minutes
		// var batInitialLevel = 80.0;
		// var batLastLevel = 5.0;
		// var batDrain = (batInitialLevel - batLastLevel) / size;
		// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
		// mHistory = new [HISTORY_MAX * elementSize];
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

	(:debug)
	function eraseAllData() {
		// $.objectStorePut("HISTORY", mHistory); // And erase the old data
		// var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
		// if (historyArray != null) {
		// 	for (var i = 0; i < historyArray.size(); i++) {
		// 		$.objectStoreErase("HISTORY_" + historyArray[i]);
		// 	}
		// 	$.objectStoreErase("HISTORY_ARRAY");
		// }
	}

	(:release)
	function eraseAllData() {
	}

	(:can_viewloop)
	function canViewLoop() {} // If it's there, we can call the viewloop functions. Without this, I get compile errors
}

(:debug)
function buildCopiedHistory() {
	// See ..\Garmin\CodeSource\temp\Data.txt
	$.objectStoreErase("HISTORY_ARRAY");

	//EDGE*/ buildCopiedHistoryInternal(1753662629, [0,970,0,547,960,0,3390,970,0,3730,980,0,4490,970,0,4511,9162,0,66022,5066,0,66322,5056,0,66922,5046,0,67822,5036,0,68422,5026,0,69322,5016,0,69922,5006,0,70522,4996,0,147612,920,0,753511,670,0,753811,4756,0,754411,4746,0,755011,4736,0,755611,4726,0,755911,4716,0,756511,4706,0,757111,4696,0,757711,4686,0,758311,4676,0,758911,4666,0,759211,4656,0,760111,4646,0,760772,540,0,761071,530,0,861138,550,0,861459,4626,0,861759,4616,0,862059,4606,0,862359,4596,0,862659,4586,0,862959,4576,0,863559,4566,0,864159,4556,0,864459,4546,0,865059,4536,0,865659,4526,0,866259,4516,0,866859,4506,0,867159,4496,0,867759,4486,0,999247,4466,0,999547,4456,0,1000147,4446,0,1000747,4436,0,1001347,4426,0,1001647,4416,0,1002247,4406,0,1002847,4396,0,1003148,4386,0,1003748,4376,0,1004348,4366,0,1004947,4356,0,1005547,4346,0,1005847,4336,0,1006488,260,0,1006548,270,0,1006604,290,0,1006668,300,0,1012674,980,0,1013011,1000,0,1022330,990,0,1024468,1000,0,1024768,990,0,1025068,980,0,1025668,970,0],[[0.001441, 0.000013, 0.000083, 0.002476], 67]);

	// buildCopiedHistoryInternal(1752655801, [0,860,0,3300,856,0,5700,852,0,8701,848,0,11807,870,1,13606,866,9,15106,862,16,17506,856,28,19307,852,0,20506,847,0,22606,843,8,24406,839,0,27108,835,0,28608,830,57,30146,826,0,32247,822,0,33746,818,7,35246,832,5,36730,846,0,38830,842,0,40931,838,0,67401,707,0,70405,702,0,74611,698,0,77611,694,0,82111,690,0,85713,686,0,89015,682,0,91715,678,0,94118,674,0,96518,670,0,98920,666,0,100120,657,0,101320,645,0,102520,637,5,104021,633,20,105824,628,0,107324,623,4,108524,619,5,110024,613,4,111374,617,0,115855,730,0,125927,811,0,126681,859,0,128935,948,0,129801,999,0,135450,994,0,136657,990,0,138457,985,0,139551,981,0,139886,984,0,141087,975,0,142287,954,0,143487,941,0,144736,968,0,148002,998,0,149499,998,0,150929,996,0,152459,992,0,153422,988,0,154922,984,0,156425,980,0,158224,976,0,160026,972,0,162125,968,0,163625,964,0,165726,960,0,167826,956,0,169626,952,0,171428,948,0,173528,944,0,176529,940,0,179829,936,0,183129,932,0,186429,928,8,188529,902,96,189730,882,6,190929,861,2,192730,857,10,194529,853,10,197230,858,0,198349,879,0,201697,874,0,204096,870,100,206196,866,0,208898,862,101,210699,851,101,212199,858,2,213790,879,0,216806,874,12,219207,870,0,221309,865,1,223408,860,3,225810,856,0,228829,852,1,230633,848,0,233452,789,0,234127,785,0,237129,781,0,238048,777,0,239686,773,0,241386,769,0,243785,765,0,246788,761,0,249488,757,0,251889,753,0,254288,749,0,257289,745,0,259990,741,0,262691,737,0,265394,733,0,268394,729,0,271095,725,0,271395,719,1,273195,715,6,274696,711,4,275836,706,52,276814,702,2,278615,697,13,280415,692,4,282520,688,3,284347,684,8,286751,680,1,287351,676,9,289751,671,103,322160,975,0,322635,968,0,323835,958,0,325335,953,0,327437,972,0,329235,987,0,331114,997,0,332615,993,0,334715,989,0,336816,985,0,338617,981,0,340418,977,0,342819,973,0,344920,969,0,347020,965,0,349121,961,0,351222,957,0,353624,953,0,356596,948,0,358425,944,0,361725,940,0,364457,936,35,367157,932,6,369259,928,15,371959,924,22,374659,920,1,376459,916,8,379460,912,1,382461,908,2,383661,903,27,384643,897,107,385463,883,34,386663,866,2,387862,843,0,390563,838,0,393865,834,4,396567,830,1,398667,826,0,401366,837,0,401978,848,0,404080,844,0,407682,840,0,410983,836,0,413983,832,0,415739,828,0,416681,821,0,419082,817,0,422082,813,0,424782,809,0,427483,805,0,430483,801,0,432583,797,0,435584,793,0,438585,789,0,440689,785,0,443387,780,0,444462,776,0,445964,772,12,448364,768,7,450464,764,3,452565,760,10,454665,756,25,456467,751,4,458866,747,32,461266,743,58,463667,739,49,466068,735,2,467268,731,15,469068,726,58,472069,721,24,474171,717,18,475371,713,22,477171,708,7,479572,703,0,481071,698,15,482572,694,2,483772,688,1,485871,683,0,488271,679,0,490373,675,0,492173,669,0,493674,663,0,494874,659,0,496073,655,0,497989,651,0,499789,647,0,501590,643,0,503390,639,0,504890,635,0,506991,631,0,508791,627,0,510591,623,0,512392,619,0,514191,615,0,516592,611,0,519291,607,0,521992,603,0,524991,599,0,527991,595,0,530864,591,0,532794,585,0,534596,579,50,539397,575,0,541497,571,15,546297,567,11,549597,563,39,552597,547,33,553797,515,26,554997,485,104,556797,473,0,557997,456,130,559197,436,135,560397,405,68,561598,371,120,562798,339,69,563998,305,10,565498,286,0,566999,282,0,568498,278,6,569605,272,0,570862,267,0,572361,262,0,574161,258,1,575362,253,0,576564,249,0,578365,245,0,578964,242,0,579864,240,0,580766,238,0,581667,236,0,582567,234,0,582962,232,0,583099,230,0,583176,227,0,583777,222,0,584676,220,0,585576,218,0,586176,216,0,587076,214,0,588277,212,0,588876,210,0,590076,208,0,590976,206,0,591576,204,0,592477,202,0,593676,200,0,594576,198,0,595476,195,0,596376,193,0,597276,191,0,598176,189,0,599077,187,0,600276,185,0,601476,183,0,602395,181,0,603295,179,0,604195,177,0,605095,175,0,605995,173,0,606896,171,0,607796,169,0,608695,167,0,609895,165,0,610495,163,0,611696,161,0,612595,159,0,613495,157,0,614396,155,0,615295,153,0,616195,151,0,617395,149,0,618295,147,0,619496,145,0,620395,143,14,620695,140,1,620815,137,21,621128,133,6,621729,131,3,622330,128,3,622931,126,5,623530,124,8,624130,122,1,624510,135,0,624630,152,0,624750,170,0,624870,187,0,624990,205,0,625110,223,0,625230,241,0,625350,258,0,625470,276,0,625590,294,0,625710,312,0,625830,329,0,626180,332,8,626781,327,28,627380,317,100,627980,300,57,628580,286,18,629180,272,1,629780,258,0,630095,255,0,630204,271,0,630324,289,0,630444,306,0,630564,324,0,630684,342,0,630804,360,0,630924,377,0,631044,395,0,631164,413,0,631284,431,0,631404,448,0,631524,466,0,631644,484,0,631764,502,0,631884,519,0,632004,537,0,632104,549,0,639975,369,0,640319,366,3,641220,364,3,642719,362,3,643619,360,5,643752,357,1,643871,353,5,643991,350,5,644111,346,3,644231,343,4,644351,340,4,644471,336,9,644591,332,6,644711,329,6,644831,325,0,644951,322,3,645071,319,8,645191,317,7,645311,314,5,645431,311,3,645551,654,4,658014,996,0,658615,994,0,659815,992,0,660415,990,0,661015,988,0,661615,986,0,662516,984,0,663716,982,0,664316,980,0,665216,978,0,666416,976,0,667617,974,0,668817,972,0,670192,970,0,670272,968,0,670392,965,0,670615,963,0,671328,961,0,672228,959,0,673428,957,0,674329,955,0,675829,953,0,677029,951,0,678229,949,0,679730,947,0,680930,945,0,682730,943,0,684230,941,0,685730,939,0,687231,937,0,688733,935,0,690234,933,0,692034,931,0,693235,929,0,694435,927,0,695935,925,0,697435,923,0,699537,921,0,701038,919,0,701890,917,0,702011,915,0,707959,839,0,709160,824,18,709760,812,27,710360,802,10,710960,789,0,712160,783,0,713661,781,0,715462,778,2,716052,776,0,716172,774,0,716292,857,0,718438,949,0,719338,956,0,720538,960,0,721138,958,0,722038,954,0,722639,958,0,722938,958,0,723539,965,0,727213,957,0,727813,955,0,728414,951,0,729013,943,0,729613,934,0,730213,926,0,730813,918,0,731413,910,0,732014,903,0,732613,897,0,733813,895,0,735615,893,4,736516,891,5,738315,889,0,739216,887,0,740416,885,0,741316,883,0,742816,897,0,743639,910,0,745439,908,0,746639,911,0,747539,913,0,748139,911,0,748582,909,0,748762,907,0,748932,909,0,749940,909,0,750612,907,0,750792,905,0,751424,961,0,752013,959,0,753213,957,0,754113,955,0,755315,953,0,756216,951,0,757116,949,0,758015,945,0,758775,941,0,758955,939,0,759075,937,0,759255,935,0,759435,933,0,759817,946,0,760417,943,0,761155,940,0,762232,937,0,763608,935,0,764332,933,0,765533,931,0,767033,929,0,768232,927,0,769732,925,0,771533,923,0,773032,921,0,774233,919,0,776033,917,0,777534,915,0,779333,913,0,780835,911,0,782336,909,0,784136,907,0,785635,905,0,787136,903,0,788935,905,0,789581,925,0,790437,923,0,791337,921,8,792838,919,5,793178,934,0,794124,949,0,795025,951,0,795324,942,21,795924,932,19,796524,924,15,797124,916,18],[[0.000081, 0.000120, 0.000236, 0.000097, 0.000624, 0.000293, 0.000093, 0.001242, 0.000364, 0.001951, 0.000162, 0.000162, 0.000131, 0.000616, 0.000268, 0.000121, 0.001177, 0.000149, 0.000128, 0.002051, 0.000396, 0.000193, 0.000189, 0.000415, 0.000855, 0.000239, 0.000147, 0.000452, 0.000303, 0.000144, 0.000081, 0.000188, 0.000192, 0.001587], 500]);
	// buildCopiedHistoryInternal(1753453525, [0,2905,16,301,2899,23,600,2893,0,785,887,0,827,885,0,1200,884,0,1802,883,0,2718,882,0,2778,881,0,2838,880,0,2898,878,0,3004,876,0,3305,875,0,3904,872,0,4204,2862,26,4504,2857,100,4804,2852,97,5104,2847,100,5405,2843,22,5704,2837,20,6004,2830,100,6304,2821,100,6605,2816,100,6905,2807,99,7204,2800,26,7504,2792,47,7804,2786,26,8104,2781,26,8404,2776,44,8705,2769,100,9004,2762,20,9304,2758,33,9604,2752,43,9904,2748,100,10204,2744,70,10504,2737,0,10694,729,0,10754,728,0,10805,727,0,11105,726,0,11706,725,0,12006,724,0,12436,757,0,12736,756,0,13036,755,56,13636,754,5,14540,753,1,15140,752,98,15739,751,38,16339,750,0,16639,749,0,17240,748,0,17839,747,0,18739,746,0,19340,745,0,19940,744,0,20454,742,0,20539,741,0,20839,740,0,21439,738,0,22339,737,0,22639,736,0,23540,735,0,24439,734,0,24739,733,0,25640,732,0,25940,731,0,26239,730,0,26540,729,0,27139,728,0,27209,727,0,27439,2724,0,27739,722,2,28039,720,0,28339,719,4,28639,718,3,28940,717,2,29240,716,0,29840,715,0,30440,714,0,31342,713,0,31942,712,0,32242,711,0,32842,710,0,33441,709,2,33741,708,0,34041,2700,4,34341,2690,2,34641,2685,1,34942,2679,1,35241,2670,0,35403,665,0,35537,664,0,35842,663,0,36141,662,0,36741,661,0,37341,660,0,37941,659,0,38541,658,0,39141,657,0,39231,656,0,39441,655,0,40041,654,0,40341,653,0,40642,652,0,41242,651,0,41541,650,0,41841,649,0,42141,648,0,42742,647,0,43641,646,0,43942,645,0,44541,644,0,45141,643,0,45441,642,0,46041,641,0,46342,640,0,46941,639,0,47241,638,0,47841,637,0,48141,636,0,48742,635,0,49042,634,0,49341,633,0,49941,632,0,50841,631,0,51141,630,0,51741,629,0,52041,628,0,52941,627,0,53542,626,0,53842,625,0,54143,624,0,54744,623,0,55043,622,0,55644,621,0,55943,620,0,56543,619,0,57143,618,0,57443,617,0,58043,616,0,58643,615,0,58943,614,0,59543,613,0,60144,612,0,60743,611,0,61643,610,0,62243,609,0,62543,608,0,63143,607,0,64044,606,0,64643,605,0,65543,604,0,66144,603,0,67043,602,0,67943,601,0,68843,600,0,69744,599,0,70343,598,0,71544,597,0,72444,596,0,73343,595,0,74543,594,0,75744,593,0,76644,592,0,76943,589,0,77843,588,0,78744,587,0,79644,586,0,80244,585,0,80843,584,0,81443,583,12,81750,2577,19,82049,2569,19,82350,2564,17,82650,2560,25,82950,2555,21,83253,2549,12,83554,2544,4,83854,2538,17,84154,2531,0,84454,522,7,84754,517,0,85054,516,2,85354,515,0,85654,514,0,86255,513,0,86411,512,0,86554,511,0,86854,510,0,87154,509,0,87754,508,73,89254,507,56,89554,2503,100,89854,2497,100,90154,2492,100,90454,2487,100,90754,2482,100,91055,2478,12,91354,2471,52,91654,2466,100,91954,2462,100,92254,2458,100,92554,2453,100,92854,2447,37,93154,2441,35,93454,2437,100,93754,2432,100,94055,2427,99,94354,2418,100,94654,2411,86,94954,2407,100,95254,2403,100,95554,2398,60,95854,391,36,96154,382,24,96454,375,12,96755,370,42,97055,369,0,97654,368,0,98254,366,0,98857,365,0,99157,364,0,99457,363,0,100058,362,0,100659,361,0,100958,360,0,101558,359,0,101859,358,0,102133,357,0,102193,355,0,102253,353,0,102313,351,0,102373,349,0,102433,347,0,102493,345,0,102553,343,0,102613,341,0,102673,339,0,102733,337,0,102793,336,0,102853,334,0,102913,332,0,102973,330,0,103058,329,0,103359,328,0,103748,327,0,103808,326,0,103868,325,0,103928,323,0,103959,322,0,103968,321,0,104259,320,0,104571,317,0,104631,316,0,104691,314,0,104811,313,0,104859,312,0,104931,311,0,104991,310,0,105051,309,0,105111,308,0,105171,307,0,105231,306,0,105291,305,0,105352,304,0,105412,303,0,105458,302,0,105531,301,0,105591,300,0,105651,299,0,105711,297,0,105831,296,0,105891,294,0,105951,293,0,106011,292,0,106071,291,0,106359,285,27,106658,278,0,106958,275,0,107259,273,0,107558,272,0,107858,271,0,108158,270,0,108458,269,0,109058,268,0,109358,267,0,109658,266,0,109958,265,0,110258,264,0,110559,263,0,110858,262,0,111158,261,0,111458,259,0,111759,257,0,112059,254,0,112359,2251,0,112659,2250,0,112959,2248,0,113296,2246,0,113596,2245,0,113897,238,0,114197,237,0,114496,235,7,114796,234,1,115396,233,5,115696,232,4,115996,231,0,116296,230,0,116597,229,0,116897,228,0,117197,227,0,117497,226,0,117797,225,0,118098,224,0,118697,223,0,118998,219,0,119298,218,0,119897,217,0,120197,216,0,120497,215,0,120798,214,0,121097,213,0,121397,212,0,121697,211,0,121997,210,0,122597,209,0,123197,208,0,123497,207,0,123797,206,0,124397,205,0,124697,204,0,124810,203,0,124870,210,0,124930,219,0,124990,228,0,124997,233,0,125050,237,0,125110,246,0,125170,255,0,125230,264,0,125290,273,0,125297,278,0,125350,282,0,125410,291,0,125470,300,0,125530,309,0,125590,318,0,125597,323,0,125650,328,0,125710,337,0,125770,346,0,125830,355,0,125890,364,0,125897,369,0,125950,373,0,126010,382,0,126037,387,0,126100,386,0,126197,2383,0,126497,2378,0,126797,2373,0,127097,2368,0,127397,361,0,127595,354,0,127628,353,0,127697,352,0,127998,351,0,128897,350,0,129198,349,0,129797,348,0,130097,347,0,130397,346,0,130997,345,0,131335,344,0,131597,343,0,132498,342,0,132798,341,0,133099,340,0,133699,339,0,134299,338,0,134600,337,0,135500,336,0,136100,335,0,136699,334,0,137299,333,0,137900,332,0,138500,331,0,138800,330,0,139100,329,0,139400,328,0,140000,327,0,140301,326,0,140600,325,0,141802,324,0,142701,323,0,143602,322,0,144201,321,0,144803,320,0,146002,319,0,146903,318,0,147503,317,0,148103,316,0,149003,315,0,149903,314,0,150203,313,0,151103,312,0,151403,311,0,152003,310,0,152304,309,0,152605,308,0,153204,307,0,153505,306,0,154105,305,0,154405,304,0,154705,303,0,155305,302,0,155605,301,0,156206,300,0,156507,299,0,157107,298,0,157707,297,0,158308,296,0,158607,295,0,159208,294,0,159807,293,0,160107,292,0,160408,291,0,160707,290,0,161607,289,0,162207,288,0,162807,287,0,163107,286,0,163707,285,0,164007,284,0,164308,283,0,165208,275,0,166107,274,0,166407,273,0,166707,2264,27,167007,2255,50,167307,2249,21,167607,2245,8,167907,2238,26,168207,2232,9,168507,2225,23,168808,2217,0,169107,206,0,169407,205,13,169707,204,0,170007,245,0,170307,290,0,170607,336,0,170907,381,0,171207,427,0,171508,472,0,171807,517,0,172108,563,0,172407,608,0,172707,654,0,174398,845,0,174458,853,0,174507,862,0,174578,870,0,174638,877,0,175108,915,0,176008,914,0,176608,913,0,177207,912,0,178107,911,0,178708,910,0,179307,909,0,179820,908,0,179908,907,0,180768,906,0,180807,905,0,181696,904,0,181730,9096,0,181749,904,0,181810,903,0,181870,902,0,182008,901,0,182307,900,0,182772,899,0,182782,898,0,183509,897,0,184108,896,0,185308,895,0,185771,894,0,185831,893,0,185891,892,0,185909,891,0,185951,890,0,186192,9081,0,186201,888,0,186809,886,0,187708,885,0,187759,9077,0,187850,884,0,187910,883,0], [[0.000849, 0.000242, 0.000139, 0.000168, 0.000279, 0.001368], 500]);
	// buildCopiedHistoryInternal(1753641833, [0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,-300,883,0,0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,18904,772,0,18968,771,0,19028,769,0,19204,768,0,19335,767,0,19503,766,0,19803,760,0,20103,748,0,20357,738,0,20403,737,0,20703,733,0,21003,732,0,21603,731,0,21787,730,0,21800,8922,0,21904,4823,0,22204,4819,0,22503,4815,0,22803,4811,0,23104,4808,0,23404,4804,0,23494,704,0,23500,8896,0,23572,702,0,23704,700,0,24004,693,0,24304,688,0,24904,687,0,25504,686,0,25804,685,0,26704,684,0,26999,682,0,27081,681,0,27305,680,0,27905,679,0,28505,678,0,28806,677,0,28990,676,0,29023,8868,0,29105,675,0,29706,674,0,30305,673,0,30605,672,0,30905,671,0,31205,670,0,31805,669,0,32105,668,0,32705,667,0,33005,666,0,33305,665,0,33606,664,0,33906,663,0,34207,662,0,34807,661,0,35107,660,0,35706,659,0,36007,658,0,36606,657,0,36906,656,0,37206,655,0,37807,654,0,38106,653,0,38706,652,0,39307,651,0,39606,650,0,40206,649,0,40806,648,0,41106,647,0,41706,646,0,42307,645,0,42606,644,0,43207,643,0,43506,642,0,44106,641,0,44706,640,0,45006,639,0,45606,638,0,46206,637,0,46506,636,0,47106,635,0,47707,634,0,48007,633,0,48606,632,0,49506,631,0,50106,630,0,50706,629,0,51307,628,0,51907,627,0,52806,626,0,53407,625,0,54006,624,0,54606,623,0,55506,622,0,56406,621,0,57006,620,0,57606,619,0,58507,618,0,59106,617,0,60007,616,0,60906,615,0,60965,8807,0,61023,614,0,61088,613,0,61148,611,0,61206,609,0,61268,607,0,61328,606,0,61388,605,0,61407,604,0,61506,4698,0,61806,601,0,62106,600,0,63307,599,0,63907,598,0,66006,594,0,66306,588,0,66521,587,0,66583,586,0,66585,585,0,66907,579,0,66936,578,0,66997,577,0,67117,576,0,67177,575,0,67297,574,0,67357,573,0,67477,572,0,67537,571,0,67657,570,0,67717,569,0,67806,568,0,67897,567,0,68017,566,0,68107,565,0,68586,564,0,68600,8756,0,68664,563,0,68724,562,0,68784,561,0,68904,560,0,68964,559,0,68975,8751,0,69307,558,0,69607,4645,14,69907,4639,8,70208,4633,5,70517,4628,14,70816,4622,19,71117,4615,15,71416,4611,43,71716,4606,16,72016,500,0,72316,494,0,72617,493,0,73517,492,0,74116,490,0,74716,489,0,75316,488,0,75616,487,0,76517,486,0,76816,485,0,77716,484,0,78617,482,0,78916,481,0,79216,480,0,79517,479,0,79816,478,0,120916,215,0,120977,213,0,121227,211,0,121826,210,0,122126,209,0,122726,208,0,123026,207,0,123328,205,0,123927,204,0,124228,203,0,124529,202,0,125129,201,0,125429,200,0,126029,199,0,126329,198,0,126929,197,0,127229,196,0,127529,195,0,127829,194,0,128129,193,0,128730,192,0,129030,191,0,129330,190,0,129930,189,0,130231,188,0,130530,187,0,131131,186,0,131431,185,0,132031,184,0,132331,183,0,132932,182,0,133232,181,0,133832,180,0,134132,179,0,134732,178,0,135033,177,0,135633,176,0,135933,175,0,136532,174,0,136833,173,0,137433,172,0,138032,171,0,138332,170,0,138632,169,0,139232,168,0,139532,167,0,140133,166,0,140432,165,0,140732,164,0,141032,163,0,141632,162,0,141932,161,0,142532,160,0,143132,159,0,143432,158,0,143733,157,0,144333,156,0,144632,155,0,145233,154,0,145832,153,0,146132,152,0,146432,150,0,146494,149,0,146554,147,0,146614,145,0,146674,143,0,146732,141,0,146794,140,0,146854,139,0,146914,137,0,146974,135,0,147032,133,0,147094,131,0,147154,130,0,147214,128,0,147274,126,0,147332,124,0,147394,122,0,147454,120,0,147514,119,0,147574,117,0,147632,115,0,147694,113,0,147754,111,0,147814,109,0,147874,107,0,147932,105,0,147994,104,0,148054,102,0,148114,100,0,148174,98,0,148232,97,0,148264,96,0,148287,95,0,148311,94,0,148532,104,0,148832,149,0,149132,194,0,149432,239,0,149732,285,0,150032,330,0,150333,376,0,150633,421,0,150933,467,0,151233,512,0,151533,4637,3,151724,4632,29,151810,4630,30,151833,4629,7,151876,4628,10,152133,4624,18,152433,4620,21,152753,4614,14,152868,514,0,152929,512,0,153053,510,0,153369,509,0,153669,507,0,153969,511,0,154269,556,0,154569,602,0,154869,647,0,155169,692,0,155469,735,0,155769,775,3,155970,774,0,156030,773,0,156056,772,0,156088,771,0,156369,765,0,156669,761,0,157570,760,0,157870,759,0,158770,758,0,159671,757,0,159970,756,0,160570,755,0,160870,754,0,161170,753,0,162070,752,0,162670,751,0,163870,750,0,164170,749,0,164770,748,0,165071,747,0,165370,746,78,166570,745,0,166703,744,0,166763,743,0,167470,742,0,168371,741,0,169270,740,0,169372,739,0,169871,738,0,170170,737,0,170770,736,60,171670,735,17,172571,734,8,173471,733,8,174372,732,0,174972,731,0,175572,730,0,175872,729,0,176173,728,0,176772,727,0,177372,726,0,178574,725,0,179174,724,0,179774,723,0,180674,722,0,181274,721,0,182174,720,0,183074,719,0,183674,718,0,184274,717,0,185474,716,0,185867,715,0,185948,714,0,186976,728,0,187275,726,4,187875,724,1,187985,723,0,190667,717,0,190727,715,0,201992,607,0,202592,606,0,203193,605,0,203792,604,0,204392,603,0,204993,602,0,205892,601,0,206492,600,0,206793,599,0,207393,598,0,207692,597,0,208592,596,0,211597,896,0,211682,894,0,211742,892,0,217539,998,0,217826,996,0,218426,995,0,218727,994,0,218947,993,0,235667,966,0,236056,965,0,236356,964,0,236655,963,0,237255,962,0,237855,961,0,238455,960,0,239055,959,0,239355,958,0,239655,957,0,239955,964,0,240558,962,0,240857,961,0,241457,960,0,241519,959,0,241579,958,0,241639,957,0,241757,956,0,241819,955,0,241939,954,0,241999,953,0,242057,952,0,242179,951,0,242239,950,0,242357,949,0,242419,948,0,242479,947,0,242599,946,0,242657,945,0,242787,949,0,242957,956,0,243257,955,0,243384,954,0,243557,958,0,243722,960,0,243858,963,0,244041,964,0,244174,966,0,244471,972,0,245098,986,0,245298,984,0,245421,988,0,245708,986,78,249621,985,0], [[0.000728, 0.000377, 0.000050], 500]);
	// buildCopiedHistoryInternal(1753891574, [0,984,0,60,983,0,120,982,0,240,981,0,300,980,0,467,979,0,768,977,0,1067,976,24,1367,975,4,1668,974,19,2267,973,0,2867,972,0,4068,971,0,4367,970,4,4668,969,15,5268,968,8,5867,967,0,6468,966,0,6767,965,0,7068,964,0,7967,963,0,8267,962,0,9467,961,0,10067,960,0,10667,959,0,11267,958,0,11867,956,5,12467,955,0,13067,954,47,13367,953,7,13667,952,13,13967,951,61,14567,950,18,15167,949,38,15467,948,60,16068,946,0,16367,945,0,16667,944,0,17267,943,0,17518,942,0,21673,924,0,22067,915,0,22968,914,0,23867,913,0,24467,5001,5,24767,4995,3,25067,4989,4,25367,4985,3,25667,4981,5,25967,4973,5,26267,4968,2,26568,4961,2,26867,4953,2,27167,4945,0,27468,4938,0,27767,834,0,28067,823,0,28718,830,0,29003,829,0,29904,828,0,30504,827,0,31105,826,0,32005,825,0,32606,824,0,32906,823,0,33205,822,0,33506,821,0,34105,820,0,34706,819,0,35305,818,0,36805,817,0,37705,816,0,38306,815,0,38906,814,0,39505,813,0,40105,812,0,40405,811,0,40706,810,0,41306,809,0,41906,808,0,42806,807,0,43406,806,0,44007,805,0,45111,843,0,45712,842,0,46312,841,0,46612,840,0,47212,839,0,48414,838,0,49615,837,0,50515,836,0,51414,835,0,52315,834,0,53215,833,0,53516,832,0,54416,831,0,55316,830,0,55617,829,0,56516,828,0,57116,827,0,58016,826,0,58617,825,0,59217,824,0,60117,823,0,60417,822,0,61018,821,0,61619,820,0,62218,819,0,63119,818,0,63419,817,0,64019,816,0,64620,815,0,65220,814,0,66120,813,0,66720,812,0,67321,811,0,67621,810,0,68522,809,0,68821,808,0,70022,807,0,70622,806,0,70922,805,0,71522,800,0,71822,798,0,72422,797,0,73322,796,0,73922,795,0,74222,794,3,74822,793,0,75422,792,44,75722,791,0,76322,790,1,76622,789,40,77223,788,4,77822,786,0,78122,785,17,78423,784,9,79022,783,0,79623,782,0,79923,781,0,80224,780,8,80824,779,1,81424,778,11,81724,777,0,82034,776,0,82634,775,0,83234,774,0,83834,773,0,84114,772,0,84117,771,0,84175,778,0,84333,777,0,84462,776,0,84761,775,0,85061,774,0,85661,773,0,85961,772,0,86538,771,0,94819,778,0,95119,777,0,95418,776,0,96019,775,0,96618,774,0,97218,773,0,97818,772,0,98418,771,0,98718,770,0,99318,769,0,99626,766,0,99663,765,0,99723,763,0,99805,762,0,99865,761,3,100229,760,0,100829,759,6,101429,758,4,101814,756,6,132800,627,0,132835,626,0,133669,661,0,134256,656,0,134556,655,0,135757,654,0,136357,653,0,136657,652,0,136957,651,0,137557,650,0,138158,649,0,138758,648,0,139057,647,0,139659,646,0,140558,645,0,141159,644,0,141758,643,0,142059,642,0,142660,641,0,142959,640,0,143559,639,0,144160,638,0,144760,637,0,145360,636,0,146260,635,0,146861,634,0,147461,633,0,147760,632,0,148360,631,0,148960,630,0,149560,629,0,150461,628,0,151060,627,0,151961,626,0,152561,625,0,153161,624,0,153761,623,0,154662,622,0,155863,621,0,156463,620,0,156763,619,0,157663,618,0,158263,617,0,158713,616,0,158774,614,0,158850,612,0,158910,610,0,159763,609,0,160064,608,0,160365,607,0,160747,605,0,160807,603,0,160867,602,0,160927,600,0,160965,599,0,160987,598,0,161047,596,0,161107,595,0,161167,593,0,161227,591,0,161264,590,0,161347,588,0,161407,586,0,161467,585,0,161527,583,0,161564,582,0,161587,581,0,161647,579,0,161707,578,0,161767,576,0,161827,574,0,161887,573,0,161947,571,0,162007,570,0,162067,568,0,162127,567,0,162165,566,0,162187,565,0,162247,564,0,162307,562,0,162359,560,0,162464,4652,11,162765,4645,100,163064,4639,100,163364,4634,8,163664,4630,65,163965,4623,31,164264,4616,8,164564,4610,6,164865,4603,27,165164,4600,8,165464,4597,30,165765,4593,21,166064,4589,7,166365,4586,6,166665,478,0,166965,473,0,167865,472,0,169065,471,0,169365,469,0,169666,468,0,170266,467,0,170565,466,0,170865,465,0,171166,464,0,171465,463,0,171765,462,0,172065,461,0,172965,460,0,173866,459,0,174166,458,0,174766,457,0,175367,456,0,175666,455,0,176566,454,0,177466,453,0,177766,452,4,178067,451,0,178666,450,0,179266,449,0,180466,448,0,181067,447,0,181367,446,0,181536,444,0,181596,443,0,181666,442,0,181966,441,0,182239,440,0,182567,439,0,183166,438,0,183767,437,0,184200,436,0,184260,435,0,184320,434,0,184366,433,0,184440,432,0,184500,431,4,184620,430,10,184680,429,14,184800,428,0,184860,427,5,184920,426,1,184980,425,11,185040,424,4,185100,423,11,185220,422,11,185266,421,11,185340,420,11,185460,419,11,185520,418,11,185640,417,5,185700,416,4,185760,415,9,185866,414,2,185940,413,8,186000,412,16,186060,411,12,186166,410,11,186238,409,8,186467,408,9,186766,407,5,187366,406,0,187966,405,0,188566,404,0,189166,403,0,189582,402,7,189642,400,5,189702,398,6,189720,397,7,189766,396,4,189781,395,5,189841,393,5,190366,392,5,190967,391,0,191266,390,4,191866,389,6,192766,388,3,193066,387,14,193666,386,0,194267,385,0,194567,384,1,195166,383,0,195467,382,0,196066,381,0,196666,380,0,196966,379,0,197867,378,5,198167,377,1,198467,376,1,199067,375,0,199367,374,0,199667,373,0,199967,372,0,200567,371,0,200867,370,0,201167,369,0,201767,368,0,202368,367,0,202667,366,0,202967,365,0,203267,364,0,203567,363,0,204167,362,0,204467,361,0,204768,359,0,205067,358,0,205367,357,0,205667,356,0,205967,354,0,206567,353,0,206867,352,0,207167,351,0,207768,350,0,208067,349,0,208367,348,0,208967,347,0,209267,346,0,209567,345,0,209868,344,0,210469,343,0,210768,342,0,211120,340,0,211180,339,0,211368,338,0,211668,337,0,211968,336,0,212568,335,0,212868,334,0,213469,333,0,213769,331,0,214370,330,0,214671,329,0,214971,328,0,215271,327,0,215871,326,0,216099,325,0,216159,324,0,216219,322,0,216279,321,0,216339,320,0,216399,319,0,216433,318,0,216450,317,0,219737,809,0,220027,808,0,220927,807,0,221526,806,0,222427,805,0,223628,804,0,224228,803,0,224829,802,0,225429,801,0,226330,800,0,227231,799,0,228131,798,0,229032,797,0,229632,796,0,230532,795,0,231432,794,0,232633,793,0,233533,792,0,234132,791,0,235032,790,0,235632,789,0,236232,788,0,237132,787,0,237433,786,0,238332,785,0,238632,784,0,239534,783,0,239834,782,1,240735,781,0,241635,780,0,241934,779,0,242535,778,0,243134,777,0,244334,776,0,244935,775,0,245534,774,0,246435,773,0,246735,772,12,247035,771,15,248235,770,0,249136,769,0,249735,768,0,250035,767,0,251235,766,0,251536,762,11,251835,761,41,253036,760,0,253336,759,0,254236,758,0,254836,756,0,255136,752,0,255436,751,13,256337,750,0,257237,749,0,258136,748,0,258436,747,0,259036,746,10,259636,745,0,260537,744,0,260837,742,72,261079,741,0,261136,740,0,261156,739,0,261436,738,5,262036,737,23,262336,736,18,263236,735,2,264136,734,5,264736,733,0,265337,732,4,266236,731,0,266836,730,0,267436,729,0,268037,728,0,268636,727,0,268866,726,0,268937,725,0,269237,724,0,269836,723,0,270136,722,0],[[0.000234, 0.000083, 0.000088, 0.000308, 0.000326, 0.000212, 0.000083], 500]);
	// buildCopiedHistoryInternal(1754162610, [0,721,0,601,720,0,1200,719,0,1500,718,0,2100,717,0,2700,716,0,3000,715,0,3600,714,0,4201,713,0,4800,712,0,5100,711,0,5401,710,0,5701,709,0,6001,708,0,6300,707,0,6601,706,0,6902,705,0,7201,704,0,7802,703,0,8402,702,0,8701,701,0,9302,700,0,9601,699,0,9901,698,0,10201,697,0,10801,696,0,11101,695,0,11401,694,0,11701,693,0,12001,692,0,12301,691,0,12601,690,0,13202,689,0,13801,688,0,14401,687,0,14701,686,0,15012,685,0,15312,684,0,15612,683,0,15773,682,0,15815,681,0,15912,680,0,16212,679,0,16513,678,0,16813,677,0,17113,676,0,17414,675,0,17713,674,0,18313,673,0,18614,672,0,18913,671,0,19213,670,0,19513,669,0,20113,667,0,20414,666,0,20714,664,0,21314,663,0,21615,662,0,21914,661,0,22516,660,0,23116,659,0,23715,658,0,24016,657,0,24615,4747,0,24915,4744,0,25215,4740,0,25515,4734,0,25815,4728,0,26115,4723,0,26415,4718,0,26715,619,0,26797,618,0,26835,617,0,26890,616,0,27016,615,0,27316,614,0,27916,613,0,28216,612,0,28816,611,0,29416,610,0,29716,609,0,30317,608,0,30918,607,0,31219,606,0,32118,605,0,32418,604,0,33319,603,0,33918,602,0,34519,601,0,34818,600,0,35718,599,0,36318,598,0,36918,597,0,37819,596,0,38419,595,0,39619,594,0,39919,593,0,40518,592,0,41118,591,0,41718,590,0,42318,589,0,43220,588,0,44120,587,0,45020,586,0,45621,585,0,46221,584,0,47122,583,0,47722,582,0,48322,581,0,49222,580,0,50124,579,0,51024,578,0,51924,577,0,53125,576,0,54025,575,0,55224,574,0,55742,573,0,56124,571,0,56425,570,1,57024,569,0,57624,568,0,58224,567,0,59424,566,0,60324,565,0,61524,564,0,62424,560,10,62725,559,11,63024,558,10,63925,557,7,64824,556,0,65424,555,0,66325,554,0,66924,553,0,67524,552,1,68125,551,3,68425,550,42,69625,549,0,70224,548,1,70524,547,0,71425,546,1,72624,545,0,73224,544,0,73825,543,0,74424,542,0,75324,541,0,76702,540,0,76825,539,0,77724,538,0,78925,537,0,79525,536,0,79825,535,10,80424,534,0,81325,533,2,82825,532,0,83724,531,0,84325,530,12,84853,529,0,85225,528,0,86125,527,0,86724,526,0,87324,525,2,88224,524,0,88824,523,0,89424,522,0,90324,521,0,90924,520,0,91824,519,0,92124,518,0,92725,517,0,93025,516,0,93324,515,0,94524,512,0,95124,511,0,96024,510,0,96924,509,0,97824,508,2,98424,507,0,99025,506,0,99625,505,0,99924,504,0,100825,503,0,101124,502,0,101724,501,0,102024,500,0,102625,499,0,103224,498,0,103284,497,0,103525,496,0,104124,495,0,104425,494,0,105025,493,0,105624,492,0,106524,491,0,107124,490,0,107424,489,0,107725,488,0,108324,487,0,108624,486,0,109224,485,0,110124,484,0,110424,483,0,110725,479,0,111025,476,0,111624,475,0,111924,4568,0,112224,4566,0,112524,4564,0,112824,465,0,113124,464,0,113725,463,0,114025,462,0,114913,461,0,114919,8653,0,115224,460,0,116124,459,0,117625,458,0,119125,457,0,120025,456,0,120926,455,0,121225,454,0,122126,453,0,123326,452,0,124225,451,0,125126,450,0,126027,449,0,127227,448,0,128127,447,0,129027,446,0,130227,445,0,131127,444,0,132328,443,0,132929,442,0,133529,441,0,134729,440,0,135329,439,0,136529,438,0,137129,437,0,137730,436,0,138329,435,0,138929,434,0,139529,433,0,140429,432,0,141030,431,0,141630,430,0,142230,429,0,142531,428,0,143132,427,0,144031,426,0,144331,425,0,144715,424,0,144749,8616,0,144815,422,0,144888,420,0,144912,419,0,145231,418,0,145531,417,0,145831,416,0,146131,415,0,146431,413,0,146732,412,0,147031,411,0,147631,409,0,147931,408,0,148232,407,0,148532,406,0,149132,405,0,149431,404,0,149732,402,0,150332,401,0,150631,398,0,150931,397,0,151532,396,0,152131,395,0,152731,394,0,153331,393,0,153631,392,18,154231,391,8,154531,390,14,154831,389,17,155432,388,36,156031,387,20,156331,386,2,156932,385,100,157231,384,10,157531,383,0,158131,382,3,158731,381,31,159031,380,3,159332,379,5,159631,378,3,160239,377,5,160540,376,3,160840,375,2,161440,373,3,162040,372,5,162339,371,0,162640,370,0,162941,369,0,163541,368,0,163841,367,0,164140,366,0,164741,365,0,165042,364,0,165342,363,0,165941,361,2,166542,360,1,167144,359,3,167444,358,2,168045,357,2,168646,356,0,168946,355,4,169547,354,1,170148,353,0,170449,352,1,171049,351,0,171350,350,22,171951,349,0,172250,348,0,172550,347,0,172851,346,66,173151,345,0,173752,344,1,174351,343,2,174652,342,2,175252,341,2,175852,340,1,176453,339,1,176753,338,2,177353,337,1,177954,336,2,178553,335,0,178854,334,0,179754,333,0,180055,332,0,180655,331,0,180955,330,1,181556,329,0,182155,328,0,182456,327,0,183056,326,0,183356,325,0,183956,324,0,184255,323,0,184555,322,0,184683,321,0,184855,320,0,185155,319,0,185455,318,0,186055,317,0,186655,316,0,186955,315,0,187256,314,1,187556,313,0,187857,312,0,188456,311,0,189057,310,0,189356,309,0,189657,308,0,190257,307,0,190856,306,0,191157,4401,0,191457,4391,0,191757,4382,0,192057,4376,0,192357,4369,0,192657,4360,0,192957,260,0,193257,259,0,193558,258,0,193858,257,0,194159,256,0,194758,255,0,195058,254,0,195358,253,0,195959,252,0,196260,250,0,196861,249,0,197160,248,0,197760,247,0,198060,246,0,198361,245,0,198661,244,0,199260,242,0,199860,241,0,200160,239,0,200760,238,0,201060,237,0,201360,236,0,201660,235,0,201960,234,0,202260,233,0,202860,232,0,203460,231,0,203761,230,0,204060,229,0,204660,228,0,204960,227,0,205260,226,0,205561,225,0,206162,224,0,206461,223,0,207062,222,0,207361,220,0,207661,219,0,207961,218,0,208561,217,0,208861,216,0,209462,215,0,210061,214,0,210362,213,0,210661,212,0,210962,211,0,211561,210,0,211861,209,0,212461,208,0,212762,207,0,213062,206,0,213361,205,0,213962,204,0,214261,203,0,214561,202,0,214861,201,0,215461,200,0,216061,199,0,216361,198,0,216661,197,0,217261,196,0,217561,195,0,218162,194,0,218462,193,0,218762,192,0,219363,191,0,219662,190,0,219963,189,0,220563,188,0,221162,187,0,221463,186,0,221762,185,0,222063,184,0,222362,183,0,222662,182,0,222962,181,0,223562,180,0,224163,179,0,224462,178,0,225062,177,0,225363,176,0,225662,175,0,226262,174,0,226862,173,0,227163,172,0,227462,171,0,228062,170,0,228362,169,0,228662,168,0,229262,181,0,229562,226,0,229862,272,0,230162,318,0,230462,363,0,230762,406,0,231063,449,0,231362,489,0,231662,528,0,231962,566,0,232262,603,0,232562,637,0,232863,661,0,233094,660,0,233126,659,0,233762,658,0,234062,657,0,234962,656,0,237063,600,0,237363,599,0,238262,598,0,238562,597,0,239162,595,0,239463,594,0,239762,593,0,240662,592,32,240962,591,8,241263,590,0,241862,589,4,242463,588,18,242762,587,65,243662,585,26,244562,584,0,245163,583,2,246062,582,0,246362,581,7,246962,580,9,247262,579,1,247862,578,0,248462,573,0,248762,571,0,249062,570,0,249662,569,0,249962,4660,41,250262,4653,25],[[0.000117, 0.000057, 0.000161, 0.000258], 500]);
	// buildCopiedHistoryInternal(1754413172, [0,4648,30,300,4645,21,601,4637,9,901,4633,29,1201,4626,21,1501,4620,20,1801,513,0,2102,506,0,2701,504,0,3001,492,0,3301,4577,38,3601,4572,45,3901,4565,42,4202,4560,50,4502,4555,40,4801,4549,35,5102,4541,65,5402,4533,63,5701,4527,62,6001,4521,89,6301,4516,83,6601,4512,66,6901,4506,17,7201,4499,58,7501,4492,53,7801,4482,51,8101,4474,100,8401,4470,100,8702,4463,48,9001,4458,38,9301,4454,73,9601,347,0,9901,340,0,10201,339,0,10801,338,9,11401,337,6,11701,336,12,12001,335,12,12601,334,10,12901,333,9,13201,332,0,13501,330,0,13801,329,0,14101,328,0,14702,327,0,15301,326,0,15665,323,0,15724,321,0,15784,320,0,15901,318,0,16502,317,0,16802,316,0,17101,315,0,17701,314,0,18301,313,0,18601,312,0,19201,311,0,19502,310,0,19802,309,0,20401,308,0,20701,307,0,21001,306,0,21301,305,0,21602,304,0,21901,303,0,22201,302,0,22502,301,0,23101,300,0,23701,299,0,24001,297,0,24338,292,0,24389,291,0,24455,290,0,24522,288,0,24642,287,0,24702,286,0,24762,285,0,24822,284,0,24942,283,0,25202,282,0,25501,281,0,25801,280,0,26402,279,0,26701,278,0,27302,277,0,27601,276,0,28201,275,0,28330,274,0,28401,273,0,28460,272,0,28501,271,0,28801,270,0,29101,4363,0,29402,4361,0,29701,4360,0,30001,4358,0,30301,4357,0,30601,4355,0,30901,4352,0,31202,251,0,31291,249,0,31358,247,0,31424,245,0,31484,243,0,31544,242,0,31604,240,0,31664,239,0,31724,237,0,31784,236,0,31844,234,0,31904,233,0,31964,232,0,32024,230,0,32084,229,0,32144,227,0,32236,225,0,32307,224,0,32322,223,0,32401,222,0,32701,214,0,33001,208,0,33301,207,0,33602,206,0,33772,205,0,33840,203,0,33901,201,0,33963,199,0,34023,197,0,34083,194,0,34143,192,0,34201,189,0,34263,187,0,34316,185,0,34332,184,0,34501,203,0,34802,249,0,35101,296,0,35401,342,0,35701,388,0,36001,435,0,36301,481,0,36601,528,0,36901,574,0,37201,621,0,37501,667,0,37802,714,0,38101,760,0,38401,807,0,38702,853,0,39001,896,0,39301,926,0,39470,940,0,39550,939,0,39602,938,0,39610,937,0,39670,935,0,39901,934,0,40501,933,0,41701,932,0,42301,931,0,42901,930,0,43201,929,0,43501,928,0,44101,927,0,45001,926,0,45601,925,0,46502,924,0,47102,923,0,48301,922,0,48901,921,0,49502,920,0,50701,919,0,51301,918,0,52201,917,0,52801,916,0,53702,915,0,54601,914,0,55801,913,0,56401,912,0,57001,911,0,57901,910,0,58801,909,0,59701,908,0,60601,907,0,61501,906,0,62701,905,0,63601,904,0,64501,903,0,65235,902,0,65402,901,0,66301,900,0,67502,899,0,68101,898,0,69002,897,0,69601,896,0,],[[0.000078], 151]);

	$.objectStoreErase("LAST_SLOPE_DATA");
}

(:debug)
function buildCopiedHistoryInternal(start, readHistory, readSlopes) {
	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
	var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
	var history = new [HISTORY_MAX * elementSize];

	var i;
	for (i = 0; i < HISTORY_MAX && i < readHistory.size() / 3 && readHistory[i * 3 + TIMESTAMP] != null; i++) {
		history[i * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
		history[i * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
		if (isSolar) {
			history[i * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
		}
	}

	historyArray.add(start);
	$.objectStorePut("HISTORY_" + start, history);

	$.objectStorePut("SLOPES_" + start, readSlopes);
	$.objectStorePut("HISTORY_ARRAY", historyArray);

	if (i == 0) {
		i = 1;
	}

	$.objectStorePut("LAST_HISTORY_KEY", [history[(i - 1) * elementSize + TIMESTAMP], history[(i - 1) * elementSize + BATTERY], (isSolar ? history[(i - 1) * elementSize + SOLAR] : null)]);
	$.objectStoreErase("LAST_SLOPE_DATA");
}

(:release)
function buildCopiedHistory() {
}

function dumpHistory(index) {
	// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
	// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	// Sys.println("Dumping history");
	// var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
	// if (historyArray != null && historyArray.size() > 0) {
	// 	var history = $.objectStoreGet("HISTORY_" + historyArray[index], null);
	// 	if (history != null) {
	// 		Sys.println(historyArray);
	// 		var start = history[0 + TIMESTAMP];
	// 		Sys.println(start);
	// 		Sys.print("[");
	// 		var historySize = history.size() / elementSize;
	// 		for (var i = 0; i < historySize; i++) {
	// 			if (history[i * elementSize + TIMESTAMP] != null) {
	// 				Sys.print(history[i * elementSize + TIMESTAMP] - start + "," + history[i * elementSize + BATTERY] + "," + (isSolar ? history[i * elementSize + SOLAR] : null));
	// 			}
	// 			else {
	// 				break;
	// 			}
	// 			if (i < historySize - 1) {
	// 				Sys.print(",");
	// 			}
	// 		}
	// 		Sys.println("]");
	// 	}

	// 	var slopes = $.objectStoreGet("SLOPES_" + historyArray[index], null);
	// 	Sys.println(slopes);
	// }
}
