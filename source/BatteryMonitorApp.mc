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

enum Theme {
    THEME_LIGHT,
    THEME_DARK
}

enum GlanceLaunchMode {
	LAUNCH_FAST,
	LAUNCH_WHOLE
}

(:glance, :background)
class BatteryMonitorApp extends App.AppBase {
	var mView;
	var mGlance;
	var mDelegate;
	var mService;
	private var mTheme as Theme; // Device theme
	private var mGlanceLaunchMode as GlanceLaunchMode; // From Settings. If we need to load everything or simply go with what was used last time (not as precise)
 
    function initialize() {
        AppBase.initialize();

        // Test for night mode
        if (System.DeviceSettings has :isNightModeEnabled) {
            mTheme = System.getDeviceSettings().isNightModeEnabled ? THEME_DARK : THEME_LIGHT;
        } else {
            mTheme = THEME_DARK;
        }

		try {
			mGlanceLaunchMode = Properties.getValue("GlanceLaunchMode");
		}
		catch (e) {
			mGlanceLaunchMode = LAUNCH_FAST;
		}
    }

    // onStart() is called on application start up
    function onStart(state) {
		//DEBUG*/ logMessage("onStart: state is " + state);

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
		//DEBUG*/ logMessage("onBackgroundData: " + data);
		var dataSize = data.size();
		//DEBUG*/ logMessage("onBackgroundData: " + dataSize);

		if (mGlanceLaunchMode == LAUNCH_FAST) { // If we're launching Glance fast, we aren't reading and clearing RECEIVED_DATA in the Glance code so keep adding to it. It will be read once we finally launch the main view
			//DEBUG*/ logMessage("onBackgroundData Fast Launch, data is " + (dataSize / 3) + " elements");
	        //DEBUG*/ logMessage("Free memory 1 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			var oldData = $.objectStoreGet("RECEIVED_DATA", []);
	        //DEBUG*/ logMessage("Free memory 2 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			var oldDataSize = oldData.size();
			if (oldDataSize > 0 && oldData[0] instanceof Toybox.Lang.Array) {
				//DEBUG*/ logMessage("Old format, clearing oldData");
				oldData = []; // If what we have is an array of arrays (old format), unfortunately, we'll ignore that data
				oldDataSize = 0;
			}

			//DEBUG*/ logMessage("Adding to " + (oldDataSize / 3) + " elements");
			oldData.addAll(data);
	        //DEBUG*/ logMessage("Free memory 3 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			data = null; // We don't need it anymore, reclaim its space
	        //DEBUG*/ logMessage("Free memory 4 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			var newDataSize = oldData.size();

			var oldCount = $.objectStoreGet("RECEIVED_DATA_COUNT", 0);
			var topCount = oldCount / 10000;
			var currentCount = newDataSize / 3;
			if (currentCount > topCount) {
				topCount = currentCount;
			}
			$.objectStorePut("RECEIVED_DATA_COUNT", (topCount * 10000 + currentCount)); // Keep how much data we potentially have (might be lowered by the 'if' below) in a separate object so the glance code can read it and deal with it

			//DEBUG*/ logMessage("Now has " + (currentCount) + " elements");
			var shrinkSteps = (newDataSize.toFloat() / (HISTORY_MAX * 3) + 1.0).toNumber(); // By how much data we'll skip to make it fit into a HISTORY_MAX size.
			//DEBUG*/ logMessage("Shrink steps is " + shrinkSteps);
			if (shrinkSteps > 1) {
				var newSize = newDataSize / shrinkSteps;
				var i;
				for (i = 0; i < newSize; i += 3) {
					var j = i * shrinkSteps; 
					oldData[i + TIMESTAMP] = oldData[j + TIMESTAMP];
					oldData[i + BATTERY] = oldData[j + BATTERY];
					oldData[i + SOLAR] = oldData[j + SOLAR];
				}

				oldData = oldData.slice(0, i); // Only keep the section we copied, disregarding what's after

		        //DEBUG*/ logMessage("Free memory 4.5 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
				//DEBUG*/ logMessage("Finished. oldData is now " + (oldData.size() / 3) + " elememts");
			}

	        //DEBUG*/ logMessage("Free memory 5 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			$.objectStoreErase("RECEIVED_DATA"); // Also help not crashing for some reason
			$.objectStorePut("RECEIVED_DATA", oldData);
		}
		else {
			//DEBUG*/ logMessage("onBackgroundData whole Launch, data is " +  + (dataSize / 3) + " elements");
	        //DEBUG*/ logMessage("Free memory 1 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
			// Store the data so the View's onUpdate function can process it
			$.objectStoreErase("RECEIVED_DATA");
			$.objectStorePut("RECEIVED_DATA", data);
		}

		//DEBUG*/ logMessage("onBackgroundData requestUpdate");
		Ui.requestUpdate();
    }    

    // onStop() is called when your application is exiting
    function onStop(state) {
		//DEBUG*/ logMessage("onStop (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));

		// Was in onHide
		if (mService == null) { // Not for the background service
			//DEBUG*/ logMessage("onStop (" + (mGlance == null ? "VW)" : "GL)"));
			if (mGlance == null && mView has :HistoryClass && mView.mHistoryClass != null) { // and not for the Glance view
				mView.mHistoryClass.saveLastData();
			}

			// Now this is for both glance and main view (mView is used for both Glance and Main view)
			if (mView.mHistoryClass != null && mView.mHistoryClass.getHistory() != null) {
				mView.mHistoryClass.storeHistory(mView.mHistoryClass.getHistoryModified());
			}
		}
    }

    // onAppInstall() is called when your application is installed
    function onAppInstall() {
		//DEBUG*/ logMessage("onAppInstall (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));
		startBackgroundService(false);
    }

    // onAppUpdate() is called when your application is Updated
    function onAppUpdate() {
		//DEBUG*/ logMessage("onAppUpdate (" + (mService != null ? "SD)" : (mGlance == null ? "VW)" : "GL)")));
		startBackgroundService(false);
	}

	function onSettingsChanged() {
		if (mView != null) {
			mView.onSettingsChanged(false);
		}

		try {
			mGlanceLaunchMode = Properties.getValue("GlanceLaunchMode");
		}
		catch (e) {
			mGlanceLaunchMode = 1;
		}

		startBackgroundService(true);
	}

    // Application handler for changes in day/night mode
    public function onNightModeChanged() {
        // Handle a change in night mode
        if (System.DeviceSettings has :isNightModeEnabled) {
            mTheme = System.getDeviceSettings().isNightModeEnabled ? THEME_DARK : THEME_LIGHT;
        } else {
            mTheme = THEME_LIGHT;
        }
        // Force a screen update.
		//DEBUG*/ logMessage("onNightModeChanged requestUpdate");
        Ui.requestUpdate();
    }

	// Start the background process if it hasn't yet
	function startBackgroundService(redo) {
		var regTime = Background.getTemporalEventRegisteredTime();
		if ( regTime == null || redo == true) {
			//DEBUG*/ logMessage("Starting BG process");
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
			//DEBUG*/ logMessage("Next BG " + (regTime.value() / 60) + " min");
		}
	}

	(:can_glance)
    function getGlanceView() {
		//DEBUG*/ logMessage("getGlanceView");

		// Tell the 'Main View' that we launched from Glance
        Storage.setValue("fromGlance", true);
		mGlance = new BatteryMonitorGlanceView();
		mView = mGlance; // So onSettingsChanged can call the view or glance onSettingsChanged code without needing to check for both
        return [mGlance];
    }

	(:can_viewloop)
	function canViewLoop() {
		return true;
	}

	(:cant_viewloop)
	function canViewLoop() {
		return false;
	}

    // Return the initial view of your application here
    function getInitialView() {	
		//DEBUG*/ logMessage("getInitialView");

		//DEBUG*/ var historyArray = $.objectStoreGet("HISTORY_ARRAY", null); $.dumpHistory(historyArray.size() - 1); return;
		//DEBUG*/ logMessage("Building fake history"); buildFakeHistory();
		//DEBUG*/ logMessage("Building copied history"); $.buildCopiedHistory(); logMessage("History built from a copy"); return;
		//DEBUG*/$.objectStorePut("RECEIVED_DATA", $.buildCopiedData()); return;

		//DEBUG*/ var historyClass = new HistoryClass(); historyClass.analyzeAndStoreData([0,861,0,600,4096+860,0,1500,4096+859,0,2400,858,0,3300,857,0,3900,858,0,4500,869,0,5400,872,0,5700,853,0,6600,852,0,7200,854,0,8100,854,0,8701,855,0,9300,857,0,10203,860,0], 15, false);

		var useBuiltinPageIndicator = true;
		try {
			useBuiltinPageIndicator = Properties.getValue("BuiltinPageIndicator");
		}
		catch (e) {
			useBuiltinPageIndicator = true;
		}

	    if ($.objectStoreGet("fromGlance", false) == true) { // Up/Down buttons work when launched from glance (or if we don't have/need buttons)
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

			if (canViewLoop() && WatchUi has :ViewLoop && useBuiltinPageIndicator) {
				var factory = new PageIndicatorFactory();
				var viewLoop = new WatchUi.ViewLoop(factory, {:page => 0, :wrap => true/*, :color => Graphics.COLOR_BLACK */});
				return [viewLoop, new PageIndicatorDelegate(viewLoop)];
			} else {
				mView = new BatteryMonitorView(false);
				mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceiveFromDelegate), false);
				return [mView , mDelegate];
			}
        }
        else { // Sucks, but we have to have an extra view so the Up/Down button work in our main view
            $.objectStorePut("fromGlance", false); // In case we change our watch setting later on that we want to start from the widget and not the glance

			if (canViewLoop() && WatchUi has :ViewLoop && useBuiltinPageIndicator) {
				var factory = new PageIndicatorFactory();
				var viewLoop = new WatchUi.ViewLoop(factory, {:page => 0, :wrap => true /*, :color => Graphics.COLOR_BLACK */});
				return [viewLoop, new PageIndicatorDelegate(viewLoop)];
				//DEBUG*/ logMessage(("Launching no glance view"));
			}
			else {
				mView = new NoGlanceView();
				mDelegate = new NoGlanceDelegate();
				return [mView , mDelegate];
			}
        }
    }

    function getServiceDelegate(){
		//DEBUG*/ logMessage("getServiceDelegate");
		mService = new BatteryMonitorServiceDelegate();
        return [mService];
    }

    // Theme accessor
	(:can_glance)
    public function getTheme() as Theme {
        return mTheme;
    }

	(:can_glance)
	public function getGlanceLaunchMode() as GlanceLaunchMode {
		return mGlanceLaunchMode;
	}
}
