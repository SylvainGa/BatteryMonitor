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
			$.analyzeAndStoreData(data, size);
		
        	Ui.requestUpdate();
		}
    }    

    // onStop() is called when your application is exiting
    function onStop(state) {
		/*DEBUG*/ logMessage("onStop (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));

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

    function getGlanceView() {
		/*DEBUG*/ logMessage("getGlanceView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getGlanceView");

		// Tell the 'Main View' that we launched from Glance
        Storage.setValue("fromGlance", true);

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			getLatestHistoryFromStorage();
		}

		mGlance = new BatteryMonitorGlanceView();
		mView = mGlance; // So onSettingsChanged can call the view or glance onSettingsChanged code without needing to check for both
        return [mGlance];
    }

    // Return the initial view of your application here
    function getInitialView() {	
		/*DEBUG*/ logMessage("getInitialView: mHistory " + (mHistory != null ? "has data" : "is null"));
		//DEBUG*/ logMessage("getInitialView");

		// If onBackgroundData hasn't fetched it, get the history
		if (mHistory == null) {
			//DEBUG*/ buildCopiedHistory();
			//DEBUG*/ buildFakeHistory();
			// $.objectStorePut("HISTORY", mHistory); // And erase the old data
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
					break;
				 }
				 else { // We had corruption? Drop it and try again
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

			var maxArrays = 5;
			try {
				maxArrays = Properties.getValue("MaxArrays");
			} catch (e) {
				maxArrays = 5;
			}

			if (historyArray.size() > maxArrays) { // But if we already have the max history arrays, drop the earliest one
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

		// Sanity check. If our previous position (mHistorySize - 2) is null, start from scratch, otherwise start from our current position to improve performance
		if (mHistorySize == null || mHistorySize >= HISTORY_MAX * elementSize || (mHistorySize > 1 && mHistory[(mHistorySize - 2) * elementSize + TIMESTAMP] == null)) {
			/*DEBUG*/ if (mHistorySize != 0) { logMessage("mHistorySize was " + mHistorySize); }
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

	(:debug)
	function buildCopiedHistory() {
		var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		var historyArray = [];
		var start = 1752038233;
		var readHistory = [0,221,0,38,220,0,105,219,0,165,217,0,225,214,0,316,212,0,617,209,0,918,201,0,1027,200,0,1087,198,0,1147,196,0,1218,194,0,1819,193,0,2119,192,0,2721,191,0,3021,190,0,3321,189,0,3622,188,0,4222,187,0,4523,186,0,4823,185,0,5124,184,0,5424,183,0,5724,182,0,6324,181,0,6624,180,0,6925,179,0,7224,178,0,7824,177,0,8124,176,0,8424,175,0,9025,174,0,9626,173,0,9925,172,0,10526,171,0,10825,170,0,11125,169,0,11725,168,0,12025,167,0,12325,166,0,12626,165,0,12926,164,0,13527,163,0,14128,162,0,14728,161,0,15328,160,0,15627,159,0,16227,158,0,16828,157,0,17128,156,0,17729,155,0,18330,154,0,18630,153,0,18930,152,0,19230,151,0,19830,150,0,20431,149,0,21032,148,0,21332,147,0,21932,146,0,22232,145,0,22833,144,0,23432,143,0,24065,142,0,24334,141,0,24634,140,0,25234,139,0,25534,138,0,26134,137,0,26435,136,8,28510,415,0,28524,414,0,28601,413,0,28661,411,0,28797,410,0,29098,409,5,30047,408,0,30107,407,0,30167,406,0,30227,405,0,30287,404,0,30347,402,0,30467,401,0,30527,400,0,30587,399,0,30647,397,4,30707,396,0,30767,395,0,30827,394,0,30887,393,0,30947,392,0,31007,391,0,31067,390,0,31126,389,0,31428,388,0,31728,387,0,32028,386,0,32628,385,1,33228,384,1,33828,383,0,34728,382,0,35628,381,1,36228,380,1,36528,379,1,37728,378,2,38328,377,24,38929,376,6,39229,375,0,39528,374,0,39828,373,0,40428,369,12,40728,360,100,41028,356,100,41328,352,100,41628,348,100,41929,343,100,42228,338,100,42528,333,100,42829,329,100,43128,324,35,43428,320,0,43661,312,0,43671,311,0,43721,310,0,43781,309,0,43841,307,0,43854,306,0,43927,304,0,43987,302,0,44047,300,0,44107,299,0,44167,297,0,44227,296,0,44287,294,2,44347,292,0,44407,291,0,44467,289,0,44527,287,0,44587,286,0,44647,284,0,44707,282,0,44767,280,0,44827,279,0,44887,277,0,44947,275,0,45007,274,0,45067,272,0,45127,270,0,45187,269,0,45247,267,0,45307,265,0,45367,263,0,45427,262,0,45487,260,0,45547,258,0,45607,256,0,45667,255,0,45970,253,0,46271,252,0,46571,251,0,46871,250,0,47472,249,0,47773,248,0,48373,247,0,48972,246,0,49273,245,0,49873,244,0,50174,243,0,50474,242,0,51075,241,0,51365,239,0,51426,238,0,51467,237,0,51472,236,0,51665,235,0,52265,234,0,52644,233,0,52690,232,0,52866,231,0,53165,230,7,53465,229,0,54065,228,26,54365,227,5,54666,226,0,54966,225,14,55265,224,0,55865,223,0,56165,222,0,56465,221,0,56766,220,0,57253,219,0,57313,218,0,57371,217,0,57673,216,0,57974,215,0,58273,214,0,58573,213,0,58873,212,3,59173,211,0,59473,210,9,59774,209,0,60074,208,0,60375,207,0,60974,196,6,61275,188,12,61574,181,10,61874,175,3,62174,168,9,62474,160,0,62774,152,0,63074,145,0,63374,138,0,63674,129,4,63974,122,0,64116,118,0,64130,117,0,64274,116,0,64574,115,2,64874,114,0,65174,113,1,65474,112,0,66074,111,0,66675,110,0,66974,109,1,67575,107,0,67874,106,0,68474,104,0,69074,103,0,69374,102,0,69674,101,0,69974,100,0,70575,99,0,70874,98,0,71474,97,0,71774,96,0,72374,95,0,72674,94,0,73274,93,0,73574,92,0,74174,91,0,74775,90,0,75075,89,0,75375,88,0,75674,87,0,75814,86,0,76176,128,0,76790,214,0,76850,223,0,76910,232,0,76970,241,0,77030,250,0,77090,259,0,77150,267,0,77210,276,0,77270,285,0,77330,294,0,77390,303,0,77450,312,0,77510,320,0,77570,329,0,77630,338,0,77690,347,0,77750,356,0,77810,364,0,77870,373,0,77930,382,0,77990,391,0,78050,400,0,78110,409,0,78153,413,0,78172,417,0,78202,421,0,79620,625,0,79742,624,0,82694,844,0,83083,843,0,83143,842,0,83203,840,0,83281,839,0,83881,838,0,85081,837,0,85382,836,0,86284,835,0,87185,834,0,88385,833,0,89585,832,0,90186,831,0,91986,830,0,92887,829,0,94088,828,0,94988,827,0,95889,826,0,97088,825,0,98288,824,0,99788,823,0,100689,822,0,101889,821,0,103090,820,0,103689,819,0,104591,818,0,105790,817,0,106036,816,0,123943,782,0,124251,781,0,124551,780,0,125151,779,0,125751,778,0,126051,777,0,126351,776,0,126951,775,0,127551,774,0,127851,773,0,128451,772,0,129051,771,0,129351,770,0,129952,769,0,130253,768,0,130523,767,0,130863,761,0,131163,756,0,131463,752,0,131763,747,0,132063,743,0,132363,740,0,132663,735,0,132963,731,0,133263,727,0,133563,722,0,133863,715,0,133940,714,0,134163,713,0,134463,712,32,134763,711,9,135363,710,6,135836,709,0,135896,708,0,135956,707,0,136039,706,1,136084,704,1,136386,703,1,136986,702,0,137587,701,0,138187,700,20,138788,699,4,139689,698,0,140288,697,0,140588,696,3,141488,695,0,142088,694,0,142689,693,0,143288,692,0,143889,691,0,144190,690,0,144790,689,0,145390,688,0,145690,687,0,146291,686,0,146590,685,0,147191,684,0,147792,683,0,148092,682,0,148992,681,0,149292,680,0,149892,679,0,149993,678,0,150192,677,1,150792,676,0,151092,675,0,151392,674,0,151992,673,0,152292,672,0,152892,671,3,153192,669,1,153492,668,0,153792,667,0,154392,666,0,154693,665,0,155293,664,0,155892,663,0,156492,662,0,157092,661,0,157392,660,0,157992,659,0,158292,658,0,158593,657,0,159193,655,0,159793,654,0,160093,653,0,160393,652,0,160993,651,0,161594,650,0,161894,648,0,162493,647,0,162793,646,0,163093,645,0,163394,644,0,163694,643,0,164295,642,0,164594,641,0,164895,640,0,165195,639,0,165495,638,0,166096,637,0,166395,636,0,166995,635,0,167295,634,0,167596,633,0,167864,632,0,167879,631,0,168196,630,0,168347,629,0,168409,628,0,168469,626,0,168506,624,0,168806,623,0,169407,622,0,170007,621,0,170307,620,0,170907,619,0,171207,618,0,171507,617,0,171808,616,0,172408,615,0,172708,614,0,173309,613,0,173609,612,0,174209,611,0,174509,610,0,175109,609,0,175410,608,0,176010,607,0,176610,606,0,177210,605,0,177810,604,0,178110,603,0,179011,602,0,179611,601,0,179911,600,0,180511,599,0,181111,598,0,182011,597,0,182611,596,0,183511,595,0,183811,594,0,184712,593,0,185912,592,0,186213,591,0,187112,590,0,188612,589,0,189512,588,0,190412,587,0,191312,586,0,191912,585,0,192812,584,0,193412,583,0,193793,582,0,194012,581,0,195512,580,0,196412,579,0,196713,578,0,197614,577,0,198214,576,1,199115,575,0,200015,574,0,200615,573,59,200915,572,6,201215,571,5,201815,570,6,202115,569,0,203015,568,0,203615,567,0,204215,566,0,204515,565,0,205115,564,0,205716,563,0,206017,562,0,206617,561,0,207217,560,0,207517,559,0,208417,558,0,209317,557,0,209917,556,0,210217,555,0,210819,554,0,211719,553,0,212319,552,0,212919,551,0,213819,550,0,214120,549,3,214721,548,0,215022,547,0,215622,546,0,216222,545,0,217423,544,5,218022,543,32,219222,542,10,219522,541,55,220122,540,16,220422,539,17,221323,538,19];
		var history = new [isSolar ? 1500 : 1000];

		for (var i = 0, j = 0; j < 500 && i < readHistory.size() / 3; i++, j++) {
			history[j * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
			history[j * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
			if (isSolar) {
				history[j * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
			}
		}
		historyArray.add(start);
		$.objectStorePut("HISTORY_" + start, history);

		start = 1752261957;
		readHistory = [0,537,0,600,536,48,1200,535,1,1500,533,1,1801,532,26,2401,531,3,3301,530,21,4201,529,5,4501,528,5,5102,527,19,5702,526,16,6302,525,12,6902,524,28,7502,523,32,7754,522,11,7814,521,18,7867,519,12,7918,518,12,8169,517,15,8469,515,0,8769,514,0,9069,513,0,9369,505,1,9669,501,2,9969,497,12,10269,493,20,10569,489,21,10870,484,66,11169,481,74,11469,476,44,11769,472,3,12070,468,3,12369,462,0,12669,452,0,12970,448,0,13270,447,6,13870,446,0,14170,445,0,15070,444,0,15670,443,0,16270,442,0,16870,441,0,17170,440,0,17770,439,0,18371,438,0,19270,437,0,19870,436,0,20471,435,0,21071,434,0,21671,433,0,22271,432,0,22871,431,0,23771,430,0,24371,429,0,24671,428,0,25571,427,0,26172,426,0,26771,425,0,27372,424,0,28272,423,0,28564,422,0,28624,421,0,28645,420,0,28945,419,0,29545,418,0,30746,417,0,31347,416,0,31947,415,0,32547,414,0,32847,413,0,33147,412,0,34048,411,0,34347,410,0,34947,409,0,35849,408,0,36752,407,0,37651,406,0,38551,405,0,39151,404,0,39752,403,0,40651,402,0,41551,401,0,42152,400,0,43052,399,0,43652,398,0,43952,397,0,44552,396,0,45452,395,0,46052,394,0,46652,393,0,47253,392,0,47553,391,0,48153,390,0,49053,389,0,49653,388,0,49953,387,0,50553,386,0,51153,385,0,51453,384,0,52053,383,0,52653,382,0,52953,381,0,53554,380,0,53855,379,0,54455,378,0,55055,377,0,55355,376,0,55955,374,0,56302,373,0,75211,316,1,75810,315,4,76410,314,2,76710,313,2,77010,312,2,77310,311,3,77610,310,0,77910,309,0,78210,308,0,78510,307,3,79411,306,1,80012,305,4,80613,304,3,80913,303,6,81213,302,13,81513,301,10,82113,299,12,82413,297,9,82713,294,0,83013,293,0,83613,292,5,83913,291,0,84513,290,2,84813,289,4,85114,287,5,85415,286,3,85715,285,0,86315,283,1,86615,282,0,86915,281,0,87516,280,1,87816,279,2,88116,278,1,88416,277,1,89016,276,0,89317,275,1,89616,274,10,90216,273,0,90516,272,0,90816,271,0,91117,270,1,91717,269,1,92317,267,0,92617,266,1,93217,265,0,93517,264,0,93817,263,0,94117,261,4,94718,260,3,95017,259,1,95317,258,0,95917,257,0,96217,256,0,96517,255,0,97117,254,0,97717,253,0,98017,252,0,98618,251,0,98918,250,0,99218,249,0,99818,248,0,100118,247,0,100418,246,0,100718,245,0,101018,244,0,101318,243,0,101618,242,0,101918,240,0,102218,239,0,102818,238,1,103118,237,0,103418,236,0,104018,235,0,104318,234,0,104618,233,0,105218,232,0,105518,231,0,105818,230,0,106118,229,0,106418,228,0,107018,227,0,107318,226,0,107618,225,0,107918,224,0,108218,223,0,108518,222,0,108818,221,0,109118,220,0,109418,219,0,109718,218,0,110018,217,0,110318,216,0,110918,215,0,111218,213,0,111518,2210,0,111818,2209,0,112118,2207,0,112418,2206,0,112718,202,0,112921,198,0,112958,197,0,113041,196,0,113054,195,0,117125,183,0,148957,40,0,149003,39,0,229664,567,0,230266,566,0,231167,565,0,231768,564,0,232668,563,0,233189,623,0,233488,625,1,233788,624,6,234388,623,1,234989,622,0,235289,621,0,235589,620,0,236134,619,0,241882,603,0,254619,507,0,254648,506,0,254703,505,1,255003,504,0,255303,503,0,255903,502,14,257403,501,13,258603,500,3,258903,499,11,259503,498,25,260704,497,0,261004,496,13,261604,495,0,261905,494,0,262504,493,12,262805,492,3,263704,491,3,264304,490,4,264605,489,0,264904,488,1,265204,487,2,265804,486,6,266404,485,1,267004,484,4,267604,483,1,267904,482,0,268204,481,0,268804,480,0,269704,479,0,270004,478,0,270904,477,0,271504,476,0,271804,475,0,272104,2464,20,272405,2454,8,272705,2444,12,273005,2433,8,273306,2424,4,273605,2414,6,273905,2405,2,274205,2396,2,274506,2386,3,274805,2376,1,275105,2367,3,275405,2357,5,275705,2347,4,276005,2337,2,276306,2327,2,276606,2318,3,276906,2308,1,277206,2298,1,277506,2288,1,277806,2279,0,278106,2271,0,278280,265,0,278296,264,0,278575,263,0,279545,259,0,279562,258,0,279792,271,0,280877,372,0,280923,371,0,299054,345,0,299954,344,0,301154,343,0,301754,342,0,302354,341,0,302954,340,0,303078,339,0,303255,338,0,303856,337,0,304155,336,0,304755,335,0,305055,334,0,305655,333,0,305955,332,0,306255,331,0,306555,330,0,306855,329,0,307455,328,0,307756,327,0,308356,326,0,308656,325,0,309257,324,0,309857,323,0,310157,322,0,310758,321,0,311058,320,0,311658,319,0,311958,318,0,312258,317,0,312858,316,0,313158,315,0,313758,314,0,314058,313,0,314358,312,0,314959,311,0,315258,310,0,315858,309,0,316158,308,0,316459,307,0,316759,306,0,317360,305,0,317961,304,0,318150,303,0,319378,300,0,319442,299,0,319502,298,0,319562,296,0,319615,294,0,319916,293,0,320217,292,0,320516,291,0,321116,290,0,321417,2283,22,321716,2273,32,322016,2265,17,322316,2260,100,322616,2253,11,322916,244,0,323216,236,0,323516,235,0,323817,234,0,324117,233,0,324717,232,0,325317,230,0,325549,229,0,325617,228,0,325917,227,0,326517,226,0,326817,225,0,327117,224,0,327717,223,0,328017,222,0,328318,221,0,328617,220,0,328917,219,0,329517,218,0,329817,217,0,330417,215,0,330717,214,0,331017,213,0,331618,212,0,331917,211,0,332218,210,0,332518,209,0,332817,208,0,333418,207,0,333718,206,5,334317,205,14,334618,204,0,334917,203,1,335218,202,0,335519,201,0,335818,200,0,336118,198,0,336418,197,0,336718,196,0,337018,195,0,337618,194,0,337918,193,0,338518,192,10,338818,191,0,339118,189,0,339418,188,0,339718,187,0,340018,186,0,340618,185,0,340918,184,0,341218,183,0,341518,182,0,342118,181,0,342718,180,0,343018,179,0,343319,178,0,343454,177,0,343514,175,0,343574,173,0,343618,172,0,344592,242,0,344892,240,0,345012,239,0,345100,238,0,347441,541,0,348677,698,0,348750,697,0,354147,954,0,354215,953,0,355503,979,0,355580,977,0,355991,975,8,356331,974,0,356631,973,0,356932,972,0,357532,971,0,357831,970,0,358132,969,0,358731,968,0,359331,967,0,359931,966,0,360231,965,0,360831,964,0,361431,963,0,361731,962,0,364132,961,0,364733,960,0,365033,959,0,365633,958,0,365918,957,0,366006,956,0,366046,955,0,366069,954,0,366129,953,0,366471,2944,0,366771,2937,0,367071,2931,0,367371,2925,0,367671,2920,0,367971,2916,0,368271,2911,0,368571,2906,0,368871,2900,0,369171,2896,0,369471,2891,0,369771,2887,0,370071,2882,0,370371,2877,0,370671,2872,0,370971,2867,0,371271,2863,0,371571,2858,0,371871,2854,0,372171,2848,0,372471,2843,0,372771,2839,0,373071,830,0,373371,819,0,373671,808,0,373688,806,0,374114,859,0,375302,858,0,376689,893,0,376856,892,0,376917,891,0,376983,889,0,377043,887,0,377344,886,0,377644,885,0,378244,884,0,378544,883,0,379444,882,0,380044,881,0,380644,880,0,380944,879,0,381544,878,0,382444,877,0,383344,876,0,383944,875,0,385144,874,0,385744,873,0,386944,872,0,387544,871,0,387844,870,0,388744,869,0,389344,868,0,389944,867,0,390844,866,0,391444,865,0,391744,864,0,392644,863,0,393244,862,0];
		history = new [isSolar ? 1500 : 1000];

		for (var i = 0, j = 0; j < 500 && i < readHistory.size() / 3; i++, j++) {
			history[j * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
			history[j * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
			if (isSolar) {
				history[j * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
			}
		}
		historyArray.add(start);
		$.objectStorePut("HISTORY_" + start, history);

		start = 1752655801;
		readHistory = [0,861,0,600,860,0,1500,859,0,2400,858,0,3300,857,0,3900,856,0,4500,855,0,5400,854,0,5700,853,0,6600,852,0,7200,851,0,8100,850,0,8701,849,0,9300,848,0,10203,847,0,11103,846,0,11807,870,0,12105,871,0,12405,870,0,13006,869,2,13606,868,0,13906,866,2,14206,865,14,14506,864,6,15106,863,15,15706,862,3,16306,861,3,16906,860,1,17506,858,1,18406,857,28,18706,855,0,19006,854,1,19307,853,0,19606,852,0,19906,851,1,20206,849,0,20506,848,0,20806,847,0,21406,846,0,21706,845,1,22606,844,3,22906,843,1,23206,842,0,23806,841,10,24406,840,0,25306,839,0,25907,838,0,26507,837,0,27108,836,0,27408,835,0,27708,834,0,28008,833,0,28608,832,57,29209,831,4,29518,829,0,29846,828,0,30146,827,0,30447,826,0,31046,825,0,31646,824,0,32247,823,0,32546,822,0,33146,821,0,33446,820,0,33746,819,0,34047,818,0,34346,817,8,34646,816,14,35246,815,5,35847,814,0,36130,813,0,36430,849,0,36730,848,0,37330,847,0,37930,845,0,38230,844,0,38830,843,0,39131,842,0,39430,841,0,40330,840,0,40931,839,0,41086,838,0,41107,837,0,67102,706,0,67401,708,0,67702,707,0,69202,706,0,69804,705,0,70405,704,0,71608,703,0,72509,701,0,73409,700,0,74611,699,0,75211,698,0,76411,697,0,77011,696,0,77611,695,0,78811,694,0,80011,693,0,81211,692,0,82111,691,0,83011,690,0,84513,689,0,85113,688,0,85713,687,0,86313,686,0,87214,685,0,88114,684,0,89015,683,0,89615,682,0,90515,681,0,91115,680,0,91715,679,0,92315,678,0,92616,677,0,93517,676,0,94118,675,0,94718,674,0,95318,673,0,95918,672,0,96518,671,0,97419,670,0,98019,669,0,98619,668,0,98920,667,0,99220,666,0,99514,665,0,99820,2660,0,100120,2658,0,100420,2657,0,100720,2656,0,101020,2655,0,101320,649,0,101620,645,0,101920,641,0,102221,639,0,102520,638,0,102821,637,0,103122,636,0,103421,635,11,104021,634,0,104322,633,9,104623,632,22,105223,631,0,105824,630,0,106123,629,0,106423,627,0,106723,626,0,107324,624,0,107624,623,0,107924,622,9,108225,621,0,108524,620,0,108824,619,0,109425,618,0,109724,617,11,110024,615,4,110624,614,0,111224,611,0,111314,610,0,111374,608,0,111525,607,0,111824,626,0,112125,625,0,115855,649,0,124862,677,0,124892,676,0,125639,784,0,125927,798,0,126220,812,0,126357,811,0,126380,810,0,126681,851,0,126982,850,0,127281,868,0,127560,867,0,128935,949,0,129632,948,0,129721,947,0,129781,946,0,129801,945,0,131513,1000,0,135326,998,0,135390,996,0,135450,995,0,135457,994,0,135757,993,0,136358,992,0,136657,991,0,136943,990,0,137257,989,0,137858,988,0,138457,986,0,138758,985,0,139357,984,0,139431,983,0,139551,982,0,139611,981,0,139731,980,0,139851,979,0,139886,978,0,140198,983,0,140487,986,0,140787,985,0,141087,983,0,141387,2973,0,141687,2968,0,141987,2964,0,142287,2959,0,142587,2955,0,142887,2950,0,143187,2946,0,143487,942,0,143787,941,0,144088,940,0,144687,939,0,144736,938,0,145056,937,0,147413,1000,0,147702,998,0,148002,997,0,148302,996,0,148902,995,0,149441,999,0,149499,998,0,150028,997,0,150329,999,0,150629,998,0,150929,997,0,151529,996,0,152129,995,0,152392,994,0,152459,993,0,152519,992,0,152823,991,0,153122,990,0,153422,989,0,153722,988,0,154022,987,0,154323,986,0,154922,985,0,155523,984,0,155824,983,0,156124,982,0,156425,981,0,156724,980,0,157024,979,0,157625,978,0,158224,977,0,158525,976,0,158825,975,0,159426,974,0,160026,973,0,160325,972,0,160925,971,0,161525,970,0,162125,969,0,162425,968,0,163026,967,0,163325,966,0,163625,965,0,164225,964,0,164825,963,0,165426,962,0,165726,961,0,166325,960,0,166925,959,0,167225,958,0,167826,957,0,168126,956,0,168726,955,0,169326,954,0,169626,953,0,170227,952,0,170527,951,0,171129,950,0,171428,949,0,172028,948,0,172628,947,0,173229,946,0,173528,945,0,174429,944,0,175029,943,0,175929,942,0,176529,941,0,177129,940,0,178329,939,0,178929,938,0,179829,937,0,180729,936,0,181330,935,0,181929,934,0,183129,933,0,183430,932,0,184629,931,0,185829,930,0,186429,929,0,187329,928,0,187629,927,0,188229,2916,17,188529,2908,10,188829,2903,60,189129,2897,72,189429,2894,71,189730,2888,1,190029,2882,6,190329,2876,0,190629,869,0,190929,862,0,191829,861,0,192129,860,5,192429,859,2,192730,858,10,193629,857,2,193929,856,0,194230,855,0,194529,854,8,194829,853,3,195429,852,4,196029,850,1,197230,849,0,197530,848,0,197857,847,0,198129,868,0,198349,867,0,200788,880,0,200828,879,0,201396,876,0,201697,875,0,202297,874,0,202897,873,0,203497,872,0,204096,871,100,204996,870,0,205296,869,0,205897,868,0,206196,867,0,206797,866,0,207096,865,0,207698,864,0,208898,863,0,209498,862,100,210098,861,3,210398,859,1,210699,857,2,211298,856,100,211598,846,3,211898,837,0,212199,836,2,212499,835,0,213359,834,0,213762,881,0,213790,880,0,214690,879,0,215304,878,0,215904,876,0,216806,875,3,217406,874,12,218007,873,0,218306,872,0,219207,871,0,219807,870,0,220408,869,0,220708,868,0,221309,867,0,221908,866,0,222508,864,0,222808,862,3,223408,861,2,224008,860,0,224309,859,1,224609,858,2,225810,857,0,226715,856,0,227015,855,1,227616,854,0,228829,853,0,229131,852,1,229731,851,0,230033,850,0,230633,849,0,230934,848,0,231234,847,0,231835,846,0,233452,790,0,233512,789,0,233524,788,0,233827,787,0,234127,786,0,235327,785,0,236227,784,0,236828,783,0,237129,782,0,237331,781,0,237391,780,0,237428,779,0,238048,778,0,238948,777,0,239549,776,0,239585,775,0,239686,774,0,239746,773,0,239885,772,0,240485,771,0,241386,770,0,241985,769,0,242886,768,0,243485,767,0,243785,766,0,244386,765,0,245588,764,0,246188,763,0,246788,762,0,247688,761,0,247988,760,0,248888,759,0,249488,758,0,249788,757,0,250688,756,0,250988,755,0,251889,754,0,252488,753,0,253088,752,0,253689,751,0,254288,750,0,255188,749,0,255788,748,0,256389,747,0,257289,746,0,258189,745,0,258789,744,0,259089,743,0,259990,742,0,260589,741,0,261189,740,0,261790,739,0,262691,738,0,263292,737,0,263892,736,0,264492,735,0,265394,734,0,266294,733,0,266894,732,0,267794,731,0,268394,730,0,268994,729,0,269895,728,0,270795,727,0,271095,726,0,271202,725,0,271262,724,0,271322,722,0,271395,720,0,271696,719,0,272295,718,0,272895,717,3,273195,716,3,273496,715,0,273796,714,7,274396,713,3,274696,712,0,275296,711,4,275702,710,0,275776,709,0,275836,708,0,275896,706,2,275914,705,1,276514,704,100,276814,703,2,277115,702,1,277715,701,0,278016,700,1,278615,699,4,278915,697,6,279515,696,1,279815,695,14,280415,694,0,280716,693,3,281321,691,3,281920,690,1,282520,689,1,283121,688,2,283747,687,0,284047,686,2,284347,685,0,284947,684,2,285248,683,10,286148,682,12,286751,681,0,286918,680,1,286978,679,1,287051,678,1,287351,677,0,287951,676,4,288251,675,10,289151,674,2,289751,672,99,290352,671,9,290952,670,8,291551,669,3];
		history = new [isSolar ? 1500 : 1000];

		for (var i = 0, j = 0; j < 500 && i < readHistory.size() / 3; i++, j++) {
			history[j * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
			history[j * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
			if (isSolar) {
				history[j * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
			}
		}
		historyArray.add(start);
		$.objectStorePut("HISTORY_" + start, history);

		start = 1752977961;
		readHistory = [0,976,0,60,975,0,120,974,0,175,972,0,475,2970,0,775,2968,0,1075,2966,0,1375,2965,0,1675,960,0,1975,957,0,2575,956,0,2875,955,0,3175,954,0,3476,953,0,4076,952,0,4726,951,0,5277,972,0,5576,971,0,6175,970,0,6475,973,0,7075,975,0,7375,973,0];
		history = new [isSolar ? 1500 : 1000];

		for (var i = 0, j = 0; j < 500 && i < readHistory.size() / 3; i++, j++) {
			history[j * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
			history[j * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
			if (isSolar) {
				history[j * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
			}
		}
		historyArray.add(start);
		$.objectStorePut("HISTORY_" + start, history);
		$.objectStorePut("HISTORY_ARRAY", historyArray);
		$.objectStorePut("LAST_HISTORY_KEY", [1752985336,973,0]);
		$.objectStoreErase("LAST_SLOPE_DATA");
	}

	(:release)
	function buildCopiedHistory() {
	}
}
