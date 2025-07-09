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
	var mIgnoreNextEvent;
    var mExit;

	function initialize(view, handler) {
		mView = view;
		mHandler = handler;
		mIgnoreNextEvent = false;
        mExit = true;

        BehaviorDelegate.initialize();
	}
	
    function onSelect() {
		/*DEBUG*/ $.analyzeAndStoreData([$.getData()], 1);

		if (System.getSystemStats().charging) {
	        mHandler.invoke(-1, 0);
		}
		else {
	        mHandler.invoke(mView.getPanelIndex(), 1);
		}
        return true;    
    }
	
    function onTap(evt) {
		onSelect();
		return true;
    }

    function onNextPage() {
		if (mIgnoreNextEvent == true) {
			mIgnoreNextEvent = false;
			return true;
		}

        var panelIndex = mView.getPanelIndex();

		panelIndex++;
		if (panelIndex >= mView.getPanelSize()) {
			panelIndex = 0;
		}
        mHandler.invoke(panelIndex, 0);

		return true;
	}

    function onPreviousPage() {
		if (mIgnoreNextEvent == true) {
			mIgnoreNextEvent = false;
			return true;
		}

        var panelIndex = mView.getPanelIndex();

		panelIndex--;
		if (panelIndex < 0) {
			panelIndex = mView.getPanelSize() - 1;
		}
        mHandler.invoke(panelIndex, 0);

		return true;
	}

	function onBack() {
		/*DEBUG*/ logMessage("onBack called");
        if (mExit) {
            return false;
        }

        mExit = true;
        return true;
	}

	function onKey(keyEvent) {
		var key = keyEvent.getKey();
		if (key == Ui.KEY_ESC) {
			/*DEBUG*/ logMessage("KEY_ESC pressed");
			mExit = true;
		}
    	if (key == Ui.KEY_ENTER){
			onSelect();
			return true;
    	}
    	
    	if (key == Ui.KEY_MENU){
    		return onMenu();
    	}
    	
		return false;
	}

	// Need to use onDrag as onSwipe illbehaves for left and right swipe, especially right which is captured by onBack first :-(
    function onDrag(dragEvent) {
		/*DEBUG*/ logMessage("onDrag called");
        mExit = false;

        var coord = dragEvent.getCoordinates();
        var panelIndex = mView.getPanelIndex();

        if (dragEvent.getType() == WatchUi.DRAG_TYPE_START) {
            mDragStartX = coord[0];
            mDragStartY = coord[1];
        }
        else if (dragEvent.getType() == WatchUi.DRAG_TYPE_STOP) {
            if (mDragStartY == null || mDragStartX == null) { // This shouldn't happened but I've seen unhandled exception for mDragStartY below!
                return true;
            }

			var xMovement = (mDragStartX - coord[0]).abs();
			var yMovement = (mDragStartY - coord[1]).abs();

			if (xMovement > yMovement) { // We 'swiped' left or right predominantly
				if (mDragStartX > coord[0]) { // Like WatchUi.SWIPE_LEFT
					/*DEBUG*/ logMessage("Swipped left");
					mHandler.invoke(panelIndex, 1);
				}
				else { // Like  WatchUi.SWIPE_RIGHT
					/*DEBUG*/ logMessage("Swipped right");
					mHandler.invoke(panelIndex, -1);
                }
			}
			else { // We 'swiped' up or down predominantly
				if (mDragStartY > coord[1]) { // Like WatchUi.SWIPE_UP
					/*DEBUG*/ logMessage("Swipped up");
					onNextPage();
					mIgnoreNextEvent = true; // Although we return 'true' below, a 'onNextPage' event would be called by itself because we swiped 'up' on the screen
				}
				else { // Like WatchUi.SWIPE_DOWN
					/*DEBUG*/ logMessage("Swipped down");
					onPreviousPage();
					mIgnoreNextEvent = true; // Although we return 'true' below, a 'onNextPage' event would be called because by itself we swiped 'down' on the screen
                }
            }
        }

        return true;
    }

    function onSwipe(swipeEvent) {
        return true; // Required otherwise a swipe right would kill the app
    }
    
    function onMenu() {
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
            //Erase
            $.objectStoreErase("HISTORY");
            $.objectStoreErase("LAST_HISTORY_KEY");
            $.objectStoreErase("LAST_VIEWED_DATA");
            $.objectStoreErase("LAST_CHARGED_DATA");
        }
		return true;
    }
}
