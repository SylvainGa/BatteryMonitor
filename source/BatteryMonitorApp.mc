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
	public var mHistoryModified;
	public var mHistoryNeedsReload;
	public var mFullHistoryNeedsRefesh;

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
		initDownSlope();

		mGlance = new BatteryMonitorGlanceView();
		mView = mGlance; // So onSettingsChanged can call the view or glance onSettingsChanged code without needing to check for both
        return [mGlance];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		/*DEBUG*/ logMessage("getInitialView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getInitialView");

		//DEBUG*/ $.dumpHistory(3);

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}
		//DEBUG*/ logMessage("Building fake history"); buildFakeHistory();
		//DEBUG*/ logMessage("Building copied history"); $.buildCopiedHistory(); logMessage("History built from a copy"); return;

		// Run the initial slope calc here as it seems to not time out, unlike the view code
		initDownSlope();

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
					var timer = new Timer.Timer();
					timer.start(method(:averageHistoryTimer), 100, false);
				}
			}
		}
		mHistoryModified = false;
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
		if (mHistorySize == null || mHistorySize >= HISTORY_MAX || (mHistorySize > 0 && mHistory[(mHistorySize - 1) * elementSize + TIMESTAMP] == null)) {
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
	// $.objectStoreErase("HISTORY_ARRAY");
	// buildCopiedHistoryInternal(1752655801, [0,861,0,600,860,0,1500,859,0,2400,858,0,3300,857,0,3900,856,0,4500,855,0,5400,854,0,5700,853,0,6600,852,0,7200,851,0,8100,850,0,8701,849,0,9300,848,0,10203,847,0,11103,846,0,11807,870,0,12105,871,0,12405,870,0,13006,869,2,13606,868,0,13906,866,2,14206,865,14,14506,864,6,15106,863,15,15706,862,3,16306,861,3,16906,860,1,17506,858,1,18406,857,28,18706,855,0,19006,854,1,19307,853,0,19606,852,0,19906,851,1,20206,849,0,20506,848,0,20806,847,0,21406,846,0,21706,845,1,22606,844,3,22906,843,1,23206,842,0,23806,841,10,24406,840,0,25306,839,0,25907,838,0,26507,837,0,27108,836,0,27408,835,0,27708,834,0,28008,833,0,28608,832,57,29209,831,4,29518,829,0,29846,828,0,30146,827,0,30447,826,0,31046,825,0,31646,824,0,32247,823,0,32546,822,0,33146,821,0,33446,820,0,33746,819,0,34047,818,0,34346,817,8,34646,816,14,35246,815,5,35847,814,0,36130,813,0,36430,849,0,36730,848,0,37330,847,0,37930,845,0,38230,844,0,38830,843,0,39131,842,0,39430,841,0,40330,840,0,40931,839,0,41086,838,0,41107,837,0,67102,706,0,67401,708,0,67702,707,0,69202,706,0,69804,705,0,70405,704,0,71608,703,0,72509,701,0,73409,700,0,74611,699,0,75211,698,0,76411,697,0,77011,696,0,77611,695,0,78811,694,0,80011,693,0,81211,692,0,82111,691,0,83011,690,0,84513,689,0,85113,688,0,85713,687,0,86313,686,0,87214,685,0,88114,684,0,89015,683,0,89615,682,0,90515,681,0,91115,680,0,91715,679,0,92315,678,0,92616,677,0,93517,676,0,94118,675,0,94718,674,0,95318,673,0,95918,672,0,96518,671,0,97419,670,0,98019,669,0,98619,668,0,98920,667,0,99220,666,0,99514,665,0,99820,2660,0,100120,2658,0,100420,2657,0,100720,2656,0,101020,2655,0,101320,649,0,101620,645,0,101920,641,0,102221,639,0,102520,638,0,102821,637,0,103122,636,0,103421,635,11,104021,634,0,104322,633,9,104623,632,22,105223,631,0,105824,630,0,106123,629,0,106423,627,0,106723,626,0,107324,624,0,107624,623,0,107924,622,9,108225,621,0,108524,620,0,108824,619,0,109425,618,0,109724,617,11,110024,615,4,110624,614,0,111224,611,0,111314,610,0,111374,608,0,111525,607,0,111824,626,0,112125,625,0,115855,649,0,124862,677,0,124892,676,0,125639,784,0,125927,798,0,126220,812,0,126357,811,0,126380,810,0,126681,851,0,126982,850,0,127281,868,0,127560,867,0,128935,949,0,129632,948,0,129721,947,0,129781,946,0,129801,945,0,131513,1000,0,135326,998,0,135390,996,0,135450,995,0,135457,994,0,135757,993,0,136358,992,0,136657,991,0,136943,990,0,137257,989,0,137858,988,0,138457,986,0,138758,985,0,139357,984,0,139431,983,0,139551,982,0,139611,981,0,139731,980,0,139851,979,0,139886,978,0,140198,983,0,140487,986,0,140787,985,0,141087,983,0,141387,2973,0,141687,2968,0,141987,2964,0,142287,2959,0,142587,2955,0,142887,2950,0,143187,2946,0,143487,942,0,143787,941,0,144088,940,0,144687,939,0,144736,938,0,145056,937,0,147413,999,0,147702,998,0,148002,997,0,148302,996,0,148902,995,0,149441,999,0,149499,998,0,150028,997,0,150329,999,0,150629,998,0,150929,997,0,151529,996,0,152129,995,0,152392,994,0,152459,993,0,152519,992,0,152823,991,0,153122,990,0,153422,989,0,153722,988,0,154022,987,0,154323,986,0,154922,985,0,155523,984,0,155824,983,0,156124,982,0,156425,981,0,156724,980,0,157024,979,0,157625,978,0,158224,977,0,158525,976,0,158825,975,0,159426,974,0,160026,973,0,160325,972,0,160925,971,0,161525,970,0,162125,969,0,162425,968,0,163026,967,0,163325,966,0,163625,965,0,164225,964,0,164825,963,0,165426,962,0,165726,961,0,166325,960,0,166925,959,0,167225,958,0,167826,957,0,168126,956,0,168726,955,0,169326,954,0,169626,953,0,170227,952,0,170527,951,0,171129,950,0,171428,949,0,172028,948,0,172628,947,0,173229,946,0,173528,945,0,174429,944,0,175029,943,0,175929,942,0,176529,941,0,177129,940,0,178329,939,0,178929,938,0,179829,937,0,180729,936,0,181330,935,0,181929,934,0,183129,933,0,183430,932,0,184629,931,0,185829,930,0,186429,929,0,187329,928,0,187629,927,0,188229,2916,17,188529,2908,10,188829,2903,60,189129,2897,72,189429,2894,71,189730,2888,1,190029,2882,6,190329,2876,0,190629,869,0,190929,862,0,191829,861,0,192129,860,5,192429,859,2,192730,858,10,193629,857,2,193929,856,0,194230,855,0,194529,854,8,194829,853,3,195429,852,4,196029,850,1,197230,849,0,197530,848,0,197857,847,0,198129,868,0,198349,867,0,200788,880,0,200828,879,0,201396,876,0,201697,875,0,202297,874,0,202897,873,0,203497,872,0,204096,871,100,204996,870,0,205296,869,0,205897,868,0,206196,867,0,206797,866,0,207096,865,0,207698,864,0,208898,863,0,209498,862,100,210098,861,3,210398,859,1,210699,857,2,211298,856,100,211598,846,3,211898,837,0,212199,836,2,212499,835,0,213359,834,0,213762,881,0,213790,880,0,214690,879,0,215304,878,0,215904,876,0,216806,875,3,217406,874,12,218007,873,0,218306,872,0,219207,871,0,219807,870,0,220408,869,0,220708,868,0,221309,867,0,221908,866,0,222508,864,0,222808,862,3,223408,861,2,224008,860,0,224309,859,1,224609,858,2,225810,857,0,226715,856,0,227015,855,1,227616,854,0,228829,853,0,229131,852,1,229731,851,0,230033,850,0,230633,849,0,230934,848,0,231234,847,0,231835,846,0,233452,790,0,233512,789,0,233524,788,0,233827,787,0,234127,786,0,235327,785,0,236227,784,0,236828,783,0,237129,782,0,237331,781,0,237391,780,0,237428,779,0,238048,778,0,238948,777,0,239549,776,0,239585,775,0,239686,774,0,239746,773,0,239885,772,0,240485,771,0,241386,770,0,241985,769,0,242886,768,0,243485,767,0,243785,766,0,244386,765,0,245588,764,0,246188,763,0,246788,762,0,247688,761,0,247988,760,0,248888,759,0,249488,758,0,249788,757,0,250688,756,0,250988,755,0,251889,754,0,252488,753,0,253088,752,0,253689,751,0,254288,750,0,255188,749,0,255788,748,0,256389,747,0,257289,746,0,258189,745,0,258789,744,0,259089,743,0,259990,742,0,260589,741,0,261189,740,0,261790,739,0,262691,738,0,263292,737,0,263892,736,0,264492,735,0,265394,734,0,266294,733,0,266894,732,0,267794,731,0,268394,730,0,268994,729,0,269895,728,0,270795,727,0,271095,726,0,271202,725,0,271262,724,0,271322,722,0,271395,720,0,271696,719,0,272295,718,0,272895,717,3,273195,716,3,273496,715,0,273796,714,7,274396,713,3,274696,712,0,275296,711,4,275702,710,0,275776,709,0,275836,708,0,275896,706,2,275914,705,1,276514,704,100,276814,703,2,277115,702,1,277715,701,0,278016,700,1,278615,699,4,278915,697,6,279515,696,1,279815,695,14,280415,694,0,280716,693,3,281321,691,3,281920,690,1,282520,689,1,283121,688,2,283747,687,0,284047,686,2,284347,685,0,284947,684,2,285248,683,10,286148,682,12,286751,681,0,286918,680,1,286978,679,1,287051,678,1,287351,677,0,287951,676,4,288251,675,10,289151,674,2,289751,672,99,290352,671,9,290952,670,8,291551,669,3], [[0.000081, 0.000120, 0.000236, 0.000097, 0.000624, 0.000293, 0.000093, 0.001242, 0.000364, 0.001951, 0.000162, 0.000162, 0.000131], 500]);
	// buildCopiedHistoryInternal(1753234166, [0,246,0,299,245,0,599,243,0,899,242,0,1499,241,0,1800,240,0,2401,239,0,2702,238,0,3302,237,0,3602,236,0,4202,235,0,4502,234,0,4597,233,0,4605,232,0,4734,231,0,4794,230,0,4811,229,0,5111,225,0,5412,223,0,6012,222,0,6311,221,0,6911,220,0,7211,219,0,7511,218,0,7811,217,0,8411,216,0,8711,215,0,9311,214,0,9912,213,0,10211,212,0,10511,211,0,11111,210,0,11711,209,0,12011,208,0,12611,207,0,12911,206,0,13211,205,0,13811,204,0,14112,203,0,14712,202,0,15311,201,0,15611,200,0,16211,199,0,16511,198,0,17111,196,0,17711,195,0,18011,194,0,18312,193,0,18911,192,0,19212,191,0,19811,190,0,20112,189,0,20712,188,0,21311,187,0,21911,186,0,22511,185,0,23111,184,0,23731,183,0,24030,182,0,24631,181,0,24930,180,0,25530,179,0,25830,178,0,26430,177,0,26730,176,0,27030,175,0,27630,174,0,27930,173,0,28531,172,0,29130,171,0,29431,170,0,30030,169,0,30330,168,0,30930,167,0,31530,166,0,31830,165,0,32130,164,0,32731,163,0,33331,162,0,33630,161,0,34230,160,0,34530,159,0,35130,158,0,35731,157,0,36031,156,0,36330,155,0,36930,154,0,37230,153,0,37830,152,0,38731,151,0,39030,150,0,39630,149,0,39930,148,0,40830,147,0,41131,146,0,41430,145,0,42030,144,24,42250,143,5,42330,141,1,42390,140,2,42450,138,16,42464,137,27,42763,134,7,43064,133,5,43364,132,2,43665,130,4,43965,129,2,44265,128,4,44566,127,9,44865,126,2,45165,125,3,45466,124,13,45765,123,2,46085,122,0,46145,131,0,46205,139,0,46265,148,0,46325,157,0,46385,166,0,46445,175,0,46505,183,0,46565,192,0,46625,201,0,46685,210,0,46745,219,0,46805,228,0,46865,237,0,46925,245,0,46985,254,0,47045,263,0,47105,272,0,47165,281,0,47225,290,0,47285,299,0,47345,308,0,47405,316,0,47465,325,0,47513,334,0,47815,333,0,48115,332,17,48416,2330,39,48715,2325,18,49015,2320,100,49315,2315,100,49615,2303,100,49915,2297,14,50215,2289,36,50515,2283,0,50815,2276,2,51115,2269,0,51415,2262,0,51715,254,0,51730,253,0,51779,258,0,51839,267,0,51899,276,0,51959,285,0,52019,293,0,52079,302,0,52139,311,0,52199,320,0,52259,329,0,52319,338,0,52379,347,0,52439,356,0,52499,364,0,52559,373,0,52619,382,0,52679,391,0,52739,400,0,52799,409,0,52859,418,0,52919,427,0,52979,436,0,53039,444,0,53099,453,0,53159,462,0,53219,471,0,53279,480,0,53339,489,0,53399,498,0,53459,507,0,53519,515,0,53579,524,0,53639,533,0,53699,542,0,53739,550,0,53795,549,0,61610,370,0,61653,369,0,61954,367,1,62255,366,5,62855,365,2,63454,364,4,64354,363,5,64655,362,1,65254,361,7,65327,359,4,65387,358,1,65446,356,1,65506,354,1,65566,353,10,65626,351,2,65686,349,9,65746,347,3,65806,346,4,65866,344,7,65926,342,2,65986,341,4,66046,339,4,66106,337,5,66166,335,13,66226,333,6,66286,332,7,66346,330,8,66406,328,4,66466,326,0,66526,325,0,66586,323,4,66646,322,2,66706,320,9,66766,319,8,66826,318,7,66886,317,7,66946,315,9,67006,314,2,67066,312,4,67126,311,3,67186,309,8,79577,999,0,79649,997,0,79950,996,0,80250,995,0,80851,994,0,81450,993,0,81750,992,0,82050,991,0,82350,990,0,82650,989,0,82950,988,0,83250,987,0,83851,986,0,84151,985,0,84752,984,0,85351,983,0,85651,982,0,85951,981,0,86552,980,0,86851,979,0,87451,978,0,88051,977,0,88652,976,0,89252,975,0,89853,974,0,90452,973,0,91352,972,0,91827,971,0,91847,970,0,91907,969,0,91967,968,0,92027,966,0,92063,965,0,92250,964,0,92364,963,0,92963,962,0,93563,961,0,93863,960,0,94464,959,0,95063,958,0,95363,957,0,95964,956,0,96564,955,0,97464,954,0,98063,953,0,98664,952,0,98964,951,0,99864,950,0,100465,949,0,101365,948,0,101966,947,0,102565,946,0,103165,945,0,104365,944,0,104666,943,0,105865,942,0,106465,941,0,107365,940,0,107966,939,0,108866,938,0,109466,937,0,110368,936,0,111268,935,0,111869,934,0,112469,933,0,113669,932,0,113970,931,0,114870,930,0,115769,929,0,116070,928,0,116669,927,0,117570,926,0,118170,925,0,119070,924,0,120271,923,0,121172,922,0,121772,921,0,122673,920,0,123273,919,0,123525,918,0,123586,917,0,123646,916,0,123706,914,0,129594,840,0,130194,839,0,130795,2829,25,131094,2820,12,131395,2814,22,131694,2810,32,131995,2805,8,132294,2799,12,132595,2794,0,132894,785,0,133795,784,0,134696,783,0,135296,782,0,136497,781,0,137097,779,0,137289,778,5,137687,777,0,137747,776,0,137807,775,0,137867,774,0,137927,773,0,139773,942,0,140073,941,0,140373,958,0,140973,957,0,141873,956,0,142173,961,0,142473,960,0,142773,959,0,143074,957,0,143673,955,0,143973,954,0,144274,957,0,144465,960,0,144573,959,0,144873,958,0,145174,966,0,147808,965,0,148848,958,0,149148,957,0,149448,956,0,149749,955,0,150049,954,0,150348,2948,0,150648,2945,0,150949,2941,0,151248,2936,0,151548,2932,0,151848,2928,0,152148,2924,0,152448,2920,0,152748,2916,0,153048,2912,0,153348,2908,0,153649,2906,0,153948,901,0,154248,898,0,154548,897,0,155448,896,0,156350,895,0,157250,894,8,157551,893,1,158151,892,9,159050,891,1,159950,890,0,160251,889,0,160851,888,0,161451,887,0,162051,886,0,162351,885,0,162951,884,0,163851,883,0,164451,882,0,164974,912,0,165274,911,0,166175,910,0,167074,909,0,167375,908,0,168274,907,0,168874,915,0,169174,914,0,169474,913,0,169774,912,0,170157,911,0,170217,910,0,170337,909,0,170397,908,0,170457,907,0,170567,906,0,170674,912,0,171575,910,0,172174,909,0,172247,908,0,172307,907,0,172427,906,0,172474,905,0,173059,962,0,173347,961,0,173648,960,0,174247,959,0,174848,958,0,175449,957,0,175748,956,0,176349,955,0,176950,954,0,177551,953,0,177851,952,0,178450,951,0,178751,950,0,179350,949,0,179650,948,0,180350,943,0,180410,942,0,180470,941,0,180590,940,0,180650,939,0,180710,938,0,180830,937,0,180890,936,0,181010,935,0,181070,934,0,181143,933,0,181452,947,0,181515,946,0,182052,945,0,182742,942,0,182790,941,0,182968,940,0,183867,938,0,184468,937,0,185243,936,0,185367,935,0,185967,934,0,186567,933,0,187168,932,0,188067,931,0,188668,930,0,189268,929,0,189867,928,0,190767,927,0,191367,926,0,192267,925,0,193168,924,0,193767,923,0,194667,922,0,195267,921,0,195868,920,0,196768,919,0,197668,918,0,198568,917,0,199169,916,0,200068,915,0,200968,914,0,201568,913,0,202470,912,0,203370,911,0,203971,910,0,204870,909,0,205771,908,0,206670,907,0,207270,906,0,207870,905,0,208771,904,0,209970,903,0,210570,902,0,210870,909,0,211216,926,0,211771,925,0,212072,924,0,212672,923,0,212972,922,0,213872,921,16,214473,920,11,214773,919,0,214813,918,0,215171,951,0,215759,950,0,216359,949,0,216660,952,0,216796,951,0,216959,2946,26,217259,2939,17,217559,2934,15,217860,2931,23,218159,2927,11,218459,2922,19,218759,2918,14,219059,2914,23], [[0.000128, 0.002051, 0.000396, 0.000193, 0.000189, 0.000415, 0.000855, 0.000239, 0.000147, 0.000452, 0.000303, 0.000144, 0.000081, 0.000188, 0.000192, 0.001587], 500]);
	// buildCopiedHistoryInternal(1753453525, [0,2905,16,301,2899,23,600,2893,0,785,887,0,827,885,0,1200,884,0,1802,883,0,2718,882,0,2778,881,0,2838,880,0,2898,878,0,3004,876,0,3305,875,0,3904,872,0,4204,2862,26,4504,2857,100,4804,2852,97,5104,2847,100,5405,2843,22,5704,2837,20,6004,2830,100,6304,2821,100,6605,2816,100,6905,2807,99,7204,2800,26,7504,2792,47,7804,2786,26,8104,2781,26,8404,2776,44,8705,2769,100,9004,2762,20,9304,2758,33,9604,2752,43,9904,2748,100,10204,2744,70,10504,2737,0,10694,729,0,10754,728,0,10805,727,0,11105,726,0,11706,725,0,12006,724,0,12436,757,0,12736,756,0,13036,755,56,13636,754,5,14540,753,1,15140,752,98,15739,751,38,16339,750,0,16639,749,0,17240,748,0,17839,747,0,18739,746,0,19340,745,0,19940,744,0,20454,742,0,20539,741,0,20839,740,0,21439,738,0,22339,737,0,22639,736,0,23540,735,0,24439,734,0,24739,733,0,25640,732,0,25940,731,0,26239,730,0,26540,729,0,27139,728,0,27209,727,0,27439,2724,0,27739,722,2,28039,720,0,28339,719,4,28639,718,3,28940,717,2,29240,716,0,29840,715,0,30440,714,0,31342,713,0,31942,712,0,32242,711,0,32842,710,0,33441,709,2,33741,708,0,34041,2700,4,34341,2690,2,34641,2685,1,34942,2679,1,35241,2670,0,35403,665,0,35537,664,0,35842,663,0,36141,662,0,36741,661,0,37341,660,0,37941,659,0,38541,658,0,39141,657,0,39231,656,0,39441,655,0,40041,654,0,40341,653,0,40642,652,0,41242,651,0,41541,650,0,41841,649,0,42141,648,0,42742,647,0,43641,646,0,43942,645,0,44541,644,0,45141,643,0,45441,642,0,46041,641,0,46342,640,0,46941,639,0,47241,638,0,47841,637,0,48141,636,0,48742,635,0,49042,634,0,49341,633,0,49941,632,0,50841,631,0,51141,630,0,51741,629,0,52041,628,0,52941,627,0,53542,626,0,53842,625,0,54143,624,0,54744,623,0,55043,622,0,55644,621,0,55943,620,0,56543,619,0,57143,618,0,57443,617,0,58043,616,0,58643,615,0,58943,614,0,59543,613,0,60144,612,0,60743,611,0,61643,610,0,62243,609,0,62543,608,0,63143,607,0,64044,606,0,64643,605,0,65543,604,0,66144,603,0,67043,602,0,67943,601,0,68843,600,0,69744,599,0,70343,598,0,71544,597,0,72444,596,0,73343,595,0,74543,594,0,75744,593,0,76644,592,0,76943,589,0,77843,588,0,78744,587,0,79644,586,0,80244,585,0,80843,584,0,81443,583,12,81750,2577,19,82049,2569,19,82350,2564,17,82650,2560,25,82950,2555,21,83253,2549,12,83554,2544,4,83854,2538,17,84154,2531,0,84454,522,7,84754,517,0,85054,516,2,85354,515,0,85654,514,0,86255,513,0,86411,512,0,86554,511,0,86854,510,0,87154,509,0,87754,508,73,89254,507,56,89554,2503,100,89854,2497,100,90154,2492,100,90454,2487,100,90754,2482,100,91055,2478,12,91354,2471,52,91654,2466,100,91954,2462,100,92254,2458,100,92554,2453,100,92854,2447,37,93154,2441,35,93454,2437,100,93754,2432,100,94055,2427,99,94354,2418,100,94654,2411,86,94954,2407,100,95254,2403,100,95554,2398,60,95854,391,36,96154,382,24,96454,375,12,96755,370,42,97055,369,0,97654,368,0,98254,366,0,98857,365,0,99157,364,0,99457,363,0,100058,362,0,100659,361,0,100958,360,0,101558,359,0,101859,358,0,102133,357,0,102193,355,0,102253,353,0,102313,351,0,102373,349,0,102433,347,0,102493,345,0,102553,343,0,102613,341,0,102673,339,0,102733,337,0,102793,336,0,102853,334,0,102913,332,0,102973,330,0,103058,329,0,103359,328,0,103748,327,0,103808,326,0,103868,325,0,103928,323,0,103959,322,0,103968,321,0,104259,320,0,104571,317,0,104631,316,0,104691,314,0,104811,313,0,104859,312,0,104931,311,0,104991,310,0,105051,309,0,105111,308,0,105171,307,0,105231,306,0,105291,305,0,105352,304,0,105412,303,0,105458,302,0,105531,301,0,105591,300,0,105651,299,0,105711,297,0,105831,296,0,105891,294,0,105951,293,0,106011,292,0,106071,291,0,106359,285,27,106658,278,0,106958,275,0,107259,273,0,107558,272,0,107858,271,0,108158,270,0,108458,269,0,109058,268,0,109358,267,0,109658,266,0,109958,265,0,110258,264,0,110559,263,0,110858,262,0,111158,261,0,111458,259,0,111759,257,0,112059,254,0,112359,2251,0,112659,2250,0,112959,2248,0,113296,2246,0,113596,2245,0,113897,238,0,114197,237,0,114496,235,7,114796,234,1,115396,233,5,115696,232,4,115996,231,0,116296,230,0,116597,229,0,116897,228,0,117197,227,0,117497,226,0,117797,225,0,118098,224,0,118697,223,0,118998,219,0,119298,218,0,119897,217,0,120197,216,0,120497,215,0,120798,214,0,121097,213,0,121397,212,0,121697,211,0,121997,210,0,122597,209,0,123197,208,0,123497,207,0,123797,206,0,124397,205,0,124697,204,0,124810,203,0,124870,210,0,124930,219,0,124990,228,0,124997,233,0,125050,237,0,125110,246,0,125170,255,0,125230,264,0,125290,273,0,125297,278,0,125350,282,0,125410,291,0,125470,300,0,125530,309,0,125590,318,0,125597,323,0,125650,328,0,125710,337,0,125770,346,0,125830,355,0,125890,364,0,125897,369,0,125950,373,0,126010,382,0,126037,387,0,126100,386,0,126197,2383,0,126497,2378,0,126797,2373,0,127097,2368,0,127397,361,0,127595,354,0,127628,353,0,127697,352,0,127998,351,0,128897,350,0,129198,349,0,129797,348,0,130097,347,0,130397,346,0,130997,345,0,131335,344,0,131597,343,0,132498,342,0,132798,341,0,133099,340,0,133699,339,0,134299,338,0,134600,337,0,135500,336,0,136100,335,0,136699,334,0,137299,333,0,137900,332,0,138500,331,0,138800,330,0,139100,329,0,139400,328,0,140000,327,0,140301,326,0,140600,325,0,141802,324,0,142701,323,0,143602,322,0,144201,321,0,144803,320,0,146002,319,0,146903,318,0,147503,317,0,148103,316,0,149003,315,0,149903,314,0,150203,313,0,151103,312,0,151403,311,0,152003,310,0,152304,309,0,152605,308,0,153204,307,0,153505,306,0,154105,305,0,154405,304,0,154705,303,0,155305,302,0,155605,301,0,156206,300,0,156507,299,0,157107,298,0,157707,297,0,158308,296,0,158607,295,0,159208,294,0,159807,293,0,160107,292,0,160408,291,0,160707,290,0,161607,289,0,162207,288,0,162807,287,0,163107,286,0,163707,285,0,164007,284,0,164308,283,0,165208,275,0,166107,274,0,166407,273,0,166707,2264,27,167007,2255,50,167307,2249,21,167607,2245,8,167907,2238,26,168207,2232,9,168507,2225,23,168808,2217,0,169107,206,0,169407,205,13,169707,204,0,170007,245,0,170307,290,0,170607,336,0,170907,381,0,171207,427,0,171508,472,0,171807,517,0,172108,563,0,172407,608,0,172707,654,0,174398,845,0,174458,853,0,174507,862,0,174578,870,0,174638,877,0,175108,915,0,176008,914,0,176608,913,0,177207,912,0,178107,911,0,178708,910,0,179307,909,0,179820,908,0,179908,907,0,180768,906,0,180807,905,0,181696,904,0,181730,9096,0,181749,904,0,181810,903,0,181870,902,0,182008,901,0,182307,900,0,182772,899,0,182782,898,0,183509,897,0,184108,896,0,185308,895,0,185771,894,0,185831,893,0,185891,892,0,185909,891,0,185951,890,0,186192,9081,0,186201,888,0,186809,886,0,187708,885,0,187759,9077,0,187850,884,0,187910,883,0], [[0.000849, 0.000242, 0.000139, 0.000168, 0.000279, 0.001368], 500]);
	// buildCopiedHistoryInternal(1753641833, [0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,-300,883,0,0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,18904,772,0,18968,771,0,19028,769,0,19204,768,0,19335,767,0,19503,766,0,19803,760,0,20103,748,0,20357,738,0,20403,737,0,20703,733,0,21003,732,0,21603,731,0,21787,730,0,21800,8922,0,21904,4823,0,22204,4819,0,22503,4815,0,22803,4811,0,23104,4808,0,23404,4804,0,23494,704,0,23500,8896,0,23572,702,0,23704,700,0,24004,693,0,24304,688,0,24904,687,0,25504,686,0,25804,685,0,26704,684,0,26999,682,0,27081,681,0,27305,680,0,27905,679,0,28505,678,0,28806,677,0,28990,676,0,29023,8868,0,29105,675,0,29706,674,0,30305,673,0,30605,672,0,30905,671,0,31205,670,0,31805,669,0,32105,668,0,32705,667,0,33005,666,0,33305,665,0,33606,664,0,33906,663,0,34207,662,0,34807,661,0,35107,660,0,35706,659,0,36007,658,0,36606,657,0,36906,656,0,37206,655,0,37807,654,0,38106,653,0,38706,652,0,39307,651,0,39606,650,0,40206,649,0,40806,648,0,41106,647,0,41706,646,0,42307,645,0,42606,644,0,43207,643,0,43506,642,0,44106,641,0,44706,640,0,45006,639,0,45606,638,0,46206,637,0,46506,636,0,47106,635,0,47707,634,0,48007,633,0,48606,632,0,49506,631,0,50106,630,0,50706,629,0,51307,628,0,51907,627,0,52806,626,0,53407,625,0,54006,624,0,54606,623,0,55506,622,0,56406,621,0,57006,620,0,57606,619,0,58507,618,0,59106,617,0,60007,616,0,60906,615,0,60965,8807,0,61023,614,0,61088,613,0,61148,611,0,61206,609,0,61268,607,0,61328,606,0,61388,605,0,61407,604,0,61506,4698,0,61806,601,0,62106,600,0,63307,599,0,63907,598,0,66006,594,0,66306,588,0,66521,587,0,66583,586,0,66585,585,0,66907,579,0,66936,578,0,66997,577,0,67117,576,0,67177,575,0,67297,574,0,67357,573,0,67477,572,0,67537,571,0,67657,570,0,67717,569,0,67806,568,0,67897,567,0,68017,566,0,68107,565,0,68586,564,0,68600,8756,0,68664,563,0,68724,562,0,68784,561,0,68904,560,0,68964,559,0,68975,8751,0,69307,558,0,69607,4645,14,69907,4639,8,70208,4633,5,70517,4628,14,70816,4622,19,71117,4615,15,71416,4611,43,71716,4606,16,72016,500,0,72316,494,0,72617,493,0,73517,492,0,74116,490,0,74716,489,0,75316,488,0,75616,487,0,76517,486,0,76816,485,0,77716,484,0,78617,482,0,78916,481,0,79216,480,0,79517,479,0,79816,478,0,120916,215,0,120977,213,0,121227,211,0,121826,210,0,122126,209,0,122726,208,0,123026,207,0,123328,205,0,123927,204,0,124228,203,0,124529,202,0,125129,201,0,125429,200,0,126029,199,0,126329,198,0,126929,197,0,127229,196,0,127529,195,0,127829,194,0,128129,193,0,128730,192,0,129030,191,0,129330,190,0,129930,189,0,130231,188,0,130530,187,0,131131,186,0,131431,185,0,132031,184,0,132331,183,0,132932,182,0,133232,181,0,133832,180,0,134132,179,0,134732,178,0,135033,177,0,135633,176,0,135933,175,0,136532,174,0,136833,173,0,137433,172,0,138032,171,0,138332,170,0,138632,169,0,139232,168,0,139532,167,0,140133,166,0,140432,165,0,140732,164,0,141032,163,0,141632,162,0,141932,161,0,142532,160,0,143132,159,0,143432,158,0,143733,157,0,144333,156,0,144632,155,0,145233,154,0,145832,153,0,146132,152,0,146432,150,0,146494,149,0,146554,147,0,146614,145,0,146674,143,0,146732,141,0,146794,140,0,146854,139,0,146914,137,0,146974,135,0,147032,133,0,147094,131,0,147154,130,0,147214,128,0,147274,126,0,147332,124,0,147394,122,0,147454,120,0,147514,119,0,147574,117,0,147632,115,0,147694,113,0,147754,111,0,147814,109,0,147874,107,0,147932,105,0,147994,104,0,148054,102,0,148114,100,0,148174,98,0,148232,97,0,148264,96,0,148287,95,0,148311,94,0,148532,104,0,148832,149,0,149132,194,0,149432,239,0,149732,285,0,150032,330,0,150333,376,0,150633,421,0,150933,467,0,151233,512,0,151533,4637,3,151724,4632,29,151810,4630,30,151833,4629,7,151876,4628,10,152133,4624,18,152433,4620,21,152753,4614,14,152868,514,0,152929,512,0,153053,510,0,153369,509,0,153669,507,0,153969,511,0,154269,556,0,154569,602,0,154869,647,0,155169,692,0,155469,735,0,155769,775,3,155970,774,0,156030,773,0,156056,772,0,156088,771,0,156369,765,0,156669,761,0,157570,760,0,157870,759,0,158770,758,0,159671,757,0,159970,756,0,160570,755,0,160870,754,0,161170,753,0,162070,752,0,162670,751,0,163870,750,0,164170,749,0,164770,748,0,165071,747,0,165370,746,78,166570,745,0,166703,744,0,166763,743,0,167470,742,0,168371,741,0,169270,740,0,169372,739,0,169871,738,0,170170,737,0,170770,736,60,171670,735,17,172571,734,8,173471,733,8,174372,732,0,174972,731,0,175572,730,0,175872,729,0,176173,728,0,176772,727,0,177372,726,0,178574,725,0,179174,724,0,179774,723,0,180674,722,0,181274,721,0,182174,720,0,183074,719,0,183674,718,0,184274,717,0,185474,716,0,185867,715,0,185948,714,0,186976,728,0,187275,726,4,187875,724,1,187985,723,0,190667,717,0,190727,715,0,201992,607,0,202592,606,0,203193,605,0,203792,604,0,204392,603,0,204993,602,0,205892,601,0,206492,600,0,206793,599,0,207393,598,0,207692,597,0,208592,596,0,211597,896,0,211682,894,0,211742,892,0,217539,998,0,217826,996,0,218426,995,0,218727,994,0,218947,993,0,235667,966,0,236056,965,0,236356,964,0,236655,963,0,237255,962,0,237855,961,0,238455,960,0,239055,959,0,239355,958,0,239655,957,0,239955,964,0,240558,962,0,240857,961,0,241457,960,0,241519,959,0,241579,958,0,241639,957,0,241757,956,0,241819,955,0,241939,954,0,241999,953,0,242057,952,0,242179,951,0,242239,950,0,242357,949,0,242419,948,0,242479,947,0,242599,946,0,242657,945,0,242787,949,0,242957,956,0,243257,955,0,243384,954,0,243557,958,0,243722,960,0,243858,963,0,244041,964,0,244174,966,0,244471,972,0,245098,986,0,245298,984,0,245421,988,0,245708,986,78,249621,985,0], [[0.000728, 0.000377, 0.000050], 500]);
	// buildCopiedHistoryInternal(1753891574, [0,984,0,60,983,0,120,982,0,240,981,0,300,980,0,467,979,0,768,977,0,1067,976,24,1367,975,4,1668,974,19,2267,973,0,2867,972,0,4068,971,0,4367,970,4,4668,969,15,5268,968,8,5867,967,0,6468,966,0,6767,965,0,7068,964,0,7967,963,0,8267,962,0,9467,961,0,10067,960,0,10667,959,0,11267,958,0,11867,956,5,12467,955,0,13067,954,47,13367,953,7,13667,952,13,13967,951,61,14567,950,18,15167,949,38,15467,948,60,16068,946,0,16367,945,0,16667,944,0,17267,943,0,17518,942,0,21673,924,0,22067,915,0,22968,914,0,23867,913,0,24467,5001,5,24767,4995,3,25067,4989,4,25367,4985,3,25667,4981,5,25967,4973,5,26267,4968,2,26568,4961,2,26867,4953,2,27167,4945,0,27468,4938,0,27767,834,0,28067,823,0,28718,830,0,29003,829,0,29904,828,0,30504,827,0,31105,826,0,32005,825,0,32606,824,0,32906,823,0,33205,822,0,33506,821,0,34105,820,0,34706,819,0,35305,818,0,36805,817,0,37705,816,0,38306,815,0,38906,814,0,39505,813,0,40105,812,0,40405,811,0,40706,810,0,41306,809,0,41906,808,0,42806,807,0,43406,806,0,44007,805,0,45111,843,0,45712,842,0,46312,841,0,46612,840,0,47212,839,0,48414,838,0,49615,837,0,50515,836,0,51414,835,0,52315,834,0,53215,833,0,53516,832,0,54416,831,0,55316,830,0,55617,829,0,56516,828,0,57116,827,0,58016,826,0,58617,825,0,59217,824,0,60117,823,0,60417,822,0,61018,821,0,61619,820,0,62218,819,0,63119,818,0,63419,817,0,64019,816,0,64620,815,0,65220,814,0,66120,813,0,66720,812,0,67321,811,0,67621,810,0,68522,809,0,68821,808,0,70022,807,0,70622,806,0,70922,805,0,71522,800,0],[[0.000073], 83]);
	// $.objectStoreErase("LAST_SLOPE_DATA");
}

(:debug)
function buildCopiedHistoryInternal(start, readHistory, readSlopes) {
	var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
	var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
	var history = new [HISTORY_MAX * elementSize];

	var i;
	for (i = 0; i < HISTORY_MAX && i < readHistory.size() / elementSize && readHistory[i * elementSize + TIMESTAMP] != null; i++) {
		history[i * elementSize + TIMESTAMP] = start + readHistory[i * elementSize + TIMESTAMP];
		history[i * elementSize + BATTERY] = readHistory[i * elementSize + BATTERY];
		if (isSolar) {
			history[i * elementSize + SOLAR] = readHistory[i * elementSize + SOLAR];
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
	var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
	if (historyArray != null && historyArray.size() > 0) {
		var history = $.objectStoreGet("HISTORY_" + historyArray[index], null);
		if (history != null) {
			Sys.println(historyArray);
			var start = history[0 + TIMESTAMP];
				Sys.println(start);
				Sys.print("[");
				var historySize = history.size() / 3;
				for (var i = 0; i < historySize; i++) {
				if (history[i*3 + TIMESTAMP] != null) {
					Sys.print(history[i*3 + TIMESTAMP] - start + "," + history[i*3 + BATTERY] + "," + history[i*3 + SOLAR]);
				}
				else {
					break;
				}
				if (i < historySize - 1) {
					Sys.print(",");
				}
			}
			Sys.println("]");
		}

		var slopes = $.objectStoreGet("SLOPES_" + historyArray[index], null);
		Sys.println(slopes);
	}
}
