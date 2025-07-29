using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;

class BatteryMonitorDelegate extends Ui.BehaviorDelegate {
	var mView;
	var mHandler;
	var mDragStartX;
	var mDragStartY;
	var mSkipNextEvent;
	var mDebounceTimer;
	var mIsViewLoop;

	function initialize(view, handler, isViewLoop) {
		mView = view;
		mHandler = handler;
		mSkipNextEvent = false;
		mIsViewLoop = isViewLoop;

        BehaviorDelegate.initialize();
	}
	
	function onBack() {
		/*DEBUG*/ logMessage("onBack");
		return false;
	}

    function onSelect() {
		/*DEBUG*/ logMessage("onSelect");

		if (System.getSystemStats().charging) {
	        mHandler.invoke(-1, 0);
		}
		else {
	        mHandler.invoke(-2, 0);
		}
        return true;    
    }
	
    function onTap(evt) {
		/*DEBUG*/ logMessage("onTap");
		onSelect();
		return true;
    }

    function onNextPage() {
		if (mSkipNextEvent == false) {
			/*DEBUG*/ logMessage("onNextPage");
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			var panelIndex = mView.getPanelIndex();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			if (viewMode == ViewMode) {
				panelIndex++;
				if (panelIndex >= mView.getPanelSize()) {
					panelIndex = 0;
				}
				mHandler.invoke(panelIndex, 0);
			}
			else {
				mHandler.invoke(panelIndex, -1);
			}
		}
		else {
			/*DEBUG*/ logMessage("Skipping this onNextPage");
		}
		return true;
	}

    function onPreviousPage() {
		if (mSkipNextEvent == false) {
			/*DEBUG*/ logMessage("onPreviousPage");
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			var panelIndex = mView.getPanelIndex();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			if (viewMode == ViewMode) {
				panelIndex--;
				if (panelIndex < 0) {
					panelIndex = mView.getPanelSize() - 1;
				}
				mHandler.invoke(panelIndex, 0);
			}
			else {
				mHandler.invoke(panelIndex, 1);
			}
		}
		else {
			/*DEBUG*/ logMessage("Skipping this onPreviousPage");
		}
		return true;
	}

	function onKey(keyEvent) {
		var key = keyEvent.getKey();
    	if (key == Ui.KEY_ENTER) {
			/*DEBUG*/ logMessage("onKey/Enter");
			onSelect();
			return true;
    	}
    	
    	else if (key == Ui.KEY_MENU) {
			/*DEBUG*/ logMessage("onKey/Menu");
    		return onMenu();
    	}
    	
    	else if (key == Ui.KEY_UP) { // Needed for GPS devices
			/*DEBUG*/ logMessage("onKey/Up");
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			var panelIndex = mView.getPanelIndex();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			mHandler.invoke(panelIndex, 1);
			return true;
    	}
    	
    	
    	else if (key == Ui.KEY_DOWN) { // Needed for GPS devices
			/*DEBUG*/ logMessage("onKey/Down");
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			var panelIndex = mView.getPanelIndex();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			mHandler.invoke(panelIndex, -1);
			return true;
    	}
    	
		/*DEBUG*/ logMessage("onKey with " + key);

		return false;
	}

	function debounceTimer() {
		mSkipNextEvent = false;
		mDebounceTimer = null;
	}

    function onDrag(dragEvent ) {
        var coord = dragEvent.getCoordinates();
	
		if (dragEvent.getType() == WatchUi.DRAG_TYPE_START) {
            mDragStartX = coord[0];
            mDragStartY = coord[1];
        }
        else if (dragEvent.getType() == WatchUi.DRAG_TYPE_STOP && mDragStartX != null && mDragStartY != null) { //I've got an unhandled exception on the next line. Was mDragStartX null? Check just in case
			var xMovement = (mDragStartX - coord[0]).abs();
			var yMovement = (mDragStartY - coord[1]).abs();

			if (xMovement > yMovement) { // We 'swiped' left or right predominantly
				if (mDragStartX > coord[0]) { // Like WatchUi.SWIPE_LEFT
					/*DEBUG*/ logMessage(("Drag left"));
					var panelIndex = mView.getPanelIndex();
					mHandler.invoke(panelIndex, 1);
				}
				else { // Like  WatchUi.SWIPE_RIGHT
					/*DEBUG*/ logMessage(("Drag right"));
					var panelIndex = mView.getPanelIndex();
					mHandler.invoke(panelIndex, -1);
				}
			}
			else { // We 'swiped' up or down predominantly
				if (mDragStartY > coord[1]) { // Like WatchUi.SWIPE_UP
					/*DEBUG*/ logMessage(("Drag up"));
					var viewMode = mView.getVSelectMode();
					var viewScreen = mView.getViewScreen();
					if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
						return false;
					}
					onNextPage();
				}
				else { // Like  WatchUi.SWIPE_DOWN
					/*DEBUG*/ logMessage(("Drag down"));
					var viewMode = mView.getVSelectMode();
					var viewScreen = mView.getViewScreen();
					if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
						return false;
					}
					onPreviousPage();
				}
			}

			mSkipNextEvent = true; // Why does a drag generate an event like onNextPage on my physical Fenix 7S Pro !?!
			mDebounceTimer = new Timer.Timer();
			mDebounceTimer.start(method(:debounceTimer), 250, false); // Debounce time is 250 msec. Any event happening within that period of time is ignored
		}

		return true;
	}

	function onSwipe(swipeEvent) {
		if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
			/*DEBUG*/ logMessage(("Swipe down"));
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			// onPreviousPage();
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
			/*DEBUG*/ logMessage(("Swipe up"));
			var viewMode = mView.getVSelectMode();
			var viewScreen = mView.getViewScreen();
			if (mIsViewLoop && (viewScreen != SCREEN_HISTORY || (viewScreen == SCREEN_HISTORY && viewMode == ViewMode))) { // We're using the view loop controls
				return false;
			}
			// onNextPage();
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_LEFT) {
			/*DEBUG*/ logMessage(("Swipe left"));
			// var panelIndex = mView.getPanelIndex();
			// mHandler.invoke(panelIndex, 1);
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_RIGHT) {
			/*DEBUG*/ logMessage(("Swipe right"));
			// var panelIndex = mView.getPanelIndex();
			// mHandler.invoke(panelIndex, -1);
		}

		return true;
	}

    function onMenu() {
		/*DEBUG*/ logMessage("onMenu");
        var dialog = new Ui.Confirmation("Erase history");
        Ui.pushView(dialog, new ConfirmationDialogDelegate(), Ui.SLIDE_IMMEDIATE);
        return true;
    }
}    

class ConfirmationDialogDelegate extends Ui.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(value) {
        if (value == 0) {
			//Keep
        }
        else {
			var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
			var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

            //Erase
			App.getApp().setHistoryNeedsReload(true);
			App.getApp().setHistoryModified(true);
			App.getApp().setHistory(new [HISTORY_MAX * elementSize]);

			var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
			var historyArraySize = historyArray.size();
			for (var index = 0; index < historyArraySize; index++) {
				$.objectStoreErase("HISTORY_" + historyArray[index]);
				$.objectStoreErase("SLOPES_" + historyArray[index]);
			}
            $.objectStoreErase("HISTORY_ARRAY");
            $.objectStoreErase("HISTORY");
            $.objectStoreErase("HISTORY_KEY");
            $.objectStoreErase("LAST_HISTORY_KEY");
            $.objectStoreErase("LAST_VIEWED_DATA");
            $.objectStoreErase("LAST_CHARGED_DATA");
			$.objectStoreErase("MARKER_DATA");
        }
		return true;
    }
}
