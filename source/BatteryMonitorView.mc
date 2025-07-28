using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Math;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;
using Toybox.Application.Properties;

enum {
	ViewMode,
	ZoomMode,
	PanMode
}

class BatteryMonitorView extends Ui.View {
    var mApp;
	var mFullHistory;
	var mFullHistorySize;
	var mHistoryStartPos;
	var mHistoryLastPos;
	var mElementSize;
	var mIsSolar;
	var mPanelOrder;
	var mPanelSize;
	var mPanelIndex;
	var mGraphSizeChange;
	var mGraphOffsetChange;
	var mShowPageMarker;
	var mGraphShowFull;
	var mCtrX, mCtrY;
	var mTimer;
	var mLastData;
	var mNowData;
	var mMarkerData;
	var mRefreshCount;
	var mFontType;
	var mFontHeight;
	var mSummaryMode;
	var mViewScreen;
	var mStartedCharging;
	var mSelectMode;
	var mSummaryProjection;
	var mDownSlopeSec;
	var mSlopeNeedsCalc;
	var mSlopesSize;
	var mTimeLastFullChargeTime;
	var mTimeLastFullChargePos;
	var mDebug;
	var mHistoryArraySize;

	var mHideChargingPopup;
	//DEBUG*/ var mDebugFont;

    function initialize() {
        View.initialize();
        mApp = App.getApp();
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
		$.objectStorePut("VIEW_RUNNING", true);

		mDebug = 0;
		mRefreshCount = 0;
		mGraphSizeChange = 0;
		mGraphOffsetChange = 0;
		mGraphShowFull = false;
		mSelectMode = ViewMode;
		mSummaryProjection = true;
		mShowPageMarker = false; // When we first display, no point showing the page marker as we are already at the first panel


		//DEBUG*/ mDebugFont = 0;
		mTimer = new Timer.Timer();
		mTimer.start(method(:refreshTimer), 5000, true); // Check every 5 seconds

    	// add data to ensure most recent data is shown and no time delay on the graph.
		mStartedCharging = false;
		mHideChargingPopup = false;
		mLastData = $.objectStoreGet("LAST_VIEWED_DATA", null);
		mMarkerData = $.objectStoreGet("MARKER_DATA", null);
		mNowData = $.getData();
		
		$.analyzeAndStoreData([mNowData], 1, false);

		onSettingsChanged();
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
		$.objectStorePut("VIEW_RUNNING", false);

		if (mTimer) {
			mTimer.stop();
		}
		mTimer = null;
		mLastData = $.getData();
		$.analyzeAndStoreData([mLastData], 1, false);
		$.objectStorePut("LAST_VIEWED_DATA", mLastData);
	}

	function onEnterSleep() {
		// Code to run when the app is about to be suspended, e.g., during USB connection
	}

	function onExitSleep() {
		// Code to run when the app resumes
	}

	function refreshTimer() as Void {
		if (System.getSystemStats().charging) {
			// Update UI, log charging status, etc.
		}

		if (mDebug < 5 || mDebug >= 10) {
			mDebug = 0;
		}

		mRefreshCount++;
		if (mRefreshCount == 12) { // Every minute, read a new set of data
			mNowData = $.getData();
			//DEBUG*/ logMessage("refreshTimer Read data " + mNowData);
			$.analyzeAndStoreData([mNowData], 1, false);
			mRefreshCount = 0;
		}

		doDownSlope();

		Ui.requestUpdate();
	}

    // Load your resources here
    function onLayout(dc) {
		// Find the right font size based on screen size
		var fontByScreenSizes = [[218, Gfx.FONT_SMALL], [240, Gfx.FONT_SMALL], [260, Gfx.FONT_SMALL], [280, Gfx.FONT_SMALL], [320, Gfx.FONT_LARGE ], [322, Gfx.FONT_LARGE], [360, Gfx.FONT_XTINY], [390, Gfx.FONT_TINY], [416, Gfx.FONT_SMALL], [454, Gfx.FONT_TINY], [470, Gfx.FONT_LARGE], [486, Gfx.FONT_TINY], [800, Gfx.FONT_MEDIUM]];
		var height = dc.getHeight();
		mFontType = null;
		for (var i = 0; i < fontByScreenSizes.size(); i++) {
			if (height == fontByScreenSizes[i][0]) {
				mFontType = fontByScreenSizes[i][1];
				break;
			}
		}

		if (mFontType == null) {
			mFontType = Gfx.FONT_SMALL; // Defaults to Small font
		}

		mFontHeight = Gfx.getFontHeight(mFontType);

    	mCtrX = dc.getWidth() / 2;
    	mCtrY = height / 2;

		// Used throughout the code to know the size of each element and if we should deal with solar data
		mIsSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		mElementSize = mIsSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		// Build our history array
		buildFullHistory();

		mSlopeNeedsCalc = false;
		doDownSlope();
    }

    function onSettingsChanged() {
		try {
			mSummaryMode = Properties.getValue("SummaryMode");
		}
		catch (e) {
			mSummaryMode = 0;
		}

        var panelOrderStr;
        try {
            panelOrderStr = Properties.getValue("PanelOrder");
        }
        catch (e) {
            Properties.setValue("PanelOrder", "1,2,3,4,5,6,7");
        }

		var defPanelOrder = [1, 2, 3, 4, 5, 6, 7];
		mPanelOrder = defPanelOrder;
		mPanelSize = MAX_SCREENS;

        if (panelOrderStr != null) {
            var array = $.to_array(panelOrderStr, ",");
            if (array.size() >= 1 && array.size() < MAX_SCREENS) {
                var i;
                for (i = 0; i < array.size(); i++) {
                    var val;
                    try {
                        val = array[i].toNumber();
                    }
                    catch (e) {
                        mPanelOrder = defPanelOrder;
                        i = MAX_SCREENS - 1;
                        break;
                    }

                    if (val != null && val > 0 && val < MAX_SCREENS) {
                        mPanelOrder[i] = val;
                    }
                    else {
                        mPanelOrder = defPanelOrder;
                        i = MAX_SCREENS - 1;
                        break;
                    }
                }

                mPanelSize = i;

                while (i < MAX_SCREENS - 1) {
                    mPanelOrder[i] = null;
                    i++;
                }
            }
        }

		mPanelIndex = 0;
		mViewScreen = mPanelOrder[0];
    }

	function onReceive(newIndex, graphSizeChange) {
		//DEBUG*/ if (graphSizeChange == 1) { mDebugFont++; if (mDebugFont > 4) { mDebugFont = 0; } }

		if (newIndex == -1) {
			mHideChargingPopup = !mHideChargingPopup;
		}
		else if (newIndex == -2) {
			if (mViewScreen == SCREEN_DATA_MAIN) {
				mSummaryProjection = !mSummaryProjection;
			}
			else if (mViewScreen == SCREEN_PROJECTION) {
				mDebug++;
			}
			else if (mViewScreen == SCREEN_HISTORY) {
				if (mDownSlopeSec != null) {
					mSelectMode += 1;
					if (mSelectMode > PanMode) {
						mSelectMode = ViewMode;
					}
					/*DEBUG*/ logMessage("Changing Select mode to " + mSelectMode);
				}
				else {
					/*DEBUG*/ logMessage("No data, not changing mode");
				}
			}
			else if (mViewScreen == SCREEN_MARKER) {
				var markerData = [$.getData()];
				markerData[0][BATTERY] |= 0x2000; // Add the marker to the data returned so we can plot a verticla line on the graph to represent it

				if (mMarkerData != null) {
					if (mMarkerData.size() == 1) { // We already have our first marker set, now record the second one
						mMarkerData.add(markerData[0]);
					}
					else { // We already have our two markers. Start over
						markerData = null;
						mMarkerData = null;
					}
				}
				else { // Setting our first marker
					mMarkerData = markerData;
				}

				$.analyzeAndStoreData(markerData, 1, true); // analyseAndStoreData deals with a null data so blindly call it even if we're null
				$.objectStorePut("MARKER_DATA", mMarkerData);
			}
		}
		else {
			if (newIndex != mPanelIndex) {
				mGraphSizeChange = 0; // If we changed panel, reset zoom of graphic view and debug count
				mGraphOffsetChange = 0; // and offset
				mGraphShowFull = false;
				mSelectMode = ViewMode; // and our view mode in the history view
				mSummaryProjection = true; // Summary shows projection

				// Restart the timer so we can reshow the page markers for 5 seconds
				mTimer.stop(); 
				mTimer.start(method(:refreshTimer), 5000, true);
				mShowPageMarker = true;
			}

			mPanelIndex = newIndex;
			mViewScreen = mPanelOrder[mPanelIndex];
		}

		if (mSelectMode == ViewMode && graphSizeChange != 0) {
			mSelectMode = ZoomMode;
		}

		if (mSelectMode == PanMode) {
			mGraphOffsetChange += graphSizeChange;
			if (mGraphOffsetChange < 0) {
				mGraphOffsetChange = 0;
			}
		}
		else {
			mGraphSizeChange += graphSizeChange;
			if (mGraphSizeChange < 0) {
				mGraphSizeChange = 0;
				mGraphShowFull = !mGraphShowFull;
			}
			else if (mGraphSizeChange > 7) {
				mGraphSizeChange = 7;
			}

			if (graphSizeChange < 0) {
				mGraphOffsetChange /= 4; // Pan to the right if we zoomed out
			}
		}
		//DEBUG*/ logMessage("mGraphSizeChange is " + mGraphSizeChange);

		Ui.requestUpdate();
	}

    // Update the view
    function onUpdate(dc) {
        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
	
		//DEBUG*/ var startTime = Sys.getTimer();

		//DEBUG*/ var fonts = [Gfx.FONT_XTINY, Gfx.FONT_TINY, Gfx.FONT_SMALL, Gfx.FONT_MEDIUM, Gfx.FONT_LARGE]; mFontType = fonts[mDebugFont]; dc.drawText(0, mCtrY, mFontType, mDebugFont, Gfx.TEXT_JUSTIFY_LEFT);

		if (buildFullHistory() == true) {
			Ui.requestUpdate(); // Time consuming, stop now and ask for another time slice
			return;
		}

		if (mTimeLastFullChargeTime == null && mFullHistory != null) {
			mTimeLastFullChargeTime = mFullHistory[0 + TIMESTAMP];
			mTimeLastFullChargePos = 0;
		}

		// Start with an empty screen 
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);		
        dc.clear();
       	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);	

		var lastChargeData = LastChargeData();
		switch (mViewScreen) {
			case SCREEN_DATA_MAIN:
				showMainPage(dc, lastChargeData);
				break;

			case SCREEN_DATA_HR:
				showDataPage(dc, SCREEN_DATA_HR, lastChargeData);
				break;

			case SCREEN_DATA_DAY:
				showDataPage(dc, SCREEN_DATA_DAY, lastChargeData);
				break;

			case SCREEN_LAST_CHARGE:
				showLastChargePage(dc, lastChargeData);
				break;
				
			case SCREEN_MARKER:
				showMarkerPage(dc);
				break;
				
			case SCREEN_HISTORY:
				drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_HISTORY);
				break;

			case SCREEN_PROJECTION:
				drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_PROJECTION);
				break;
		}

		// If charging, show its popup over any screen
		if (System.getSystemStats().charging) {
			if (mStartedCharging == false) {
				mStartedCharging = true;
				$.analyzeAndStoreData([$.getData()], 1, false);
			}
			if (mHideChargingPopup == false) {
				showChargingPopup(dc);
			}
		}
		else {
			mHideChargingPopup = false;

			if (mStartedCharging == true) {
				mStartedCharging = false;

				onUpdate(dc); // Redraw right away without the charging popup
			}
		}

		// Show page indicator
		if (mShowPageMarker) {
			if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_RECTANGLE) {
				var steps = mCtrY / MAX_SCREENS;
				var xPos = mCtrX / 20;
				var yPos = mCtrY + steps * mPanelSize / 2 - steps / 2;

				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.setPenWidth(1);
				for (var i = 0; i < mPanelSize; i++, yPos -= steps) {
					dc.drawCircle(xPos, yPos, mCtrX / 20);
					if (i + 1 == mViewScreen) {
						dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
						dc.fillCircle(xPos, yPos, mCtrX / 30);
						dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
					}
				}
			}
			else {
				var radius = mCtrX -  mCtrX / 30;
				var inc = 60.0 / MAX_SCREENS;
				var angle = 270.0 + inc * mPanelSize / 2.0 - inc / 2.0;

				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.setPenWidth(1);
				for (var i = 0; i < mPanelSize; i++, angle -= inc) {
					var xPos = mCtrX + radius * Math.sin(Math.toRadians(angle));
					var yPos = mCtrY + radius * Math.cos(Math.toRadians(angle));
					dc.drawCircle(xPos, yPos, mCtrX / 30);
					if (i + 1 == mViewScreen) {
						dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
						dc.fillCircle(xPos, yPos, mCtrX / 40);
						dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
					}
				}
			}

			mShowPageMarker = false; // Don't show again until we switch view
		}
		//DEBUG*/ var endTime = Sys.getTimer(); logMessage("onUpdate for " + mViewScreen + " took " + (endTime - startTime) + "msec");
    }

	function doHeader(dc, whichView, battery, onlyBattery) {
		//! Display current charge level with the appropriate color
		var colorBat = getBatteryColor(battery);
		dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
		dc.drawText(mCtrX, 20 * mCtrY * 2 / 240, Gfx.FONT_NUMBER_MILD, battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
    	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);

		var scale = mCtrY * 2.0 / 240.0; // 240 was the default resolution of the watch used at the time this widget was created
		var yPos = 35 * scale;

		if (onlyBattery) {
			return yPos;
		}

		if (mDownSlopeSec != null) {
			var downSlopeStr;
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			if (whichView == SCREEN_DATA_HR) {
				dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.Remaining), Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				if (mStartedCharging == true) {
					downSlopeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
				}
				else {
					var downSlopeMin = mDownSlopeSec * 60;
					downSlopeStr = $.minToStr(battery / downSlopeMin, true);
				}
				dc.drawText(mCtrX, yPos, mFontType, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
			}
			else if (whichView == SCREEN_DATA_DAY) {
				dc.drawText(mCtrX, yPos, mFontType, mStartedCharging == true ? Ui.loadResource(Rez.Strings.Charging) : Ui.loadResource(Rez.Strings.Discharging), Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				if (mStartedCharging == true) {
					downSlopeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
				}
				else {
					var downSlopeHours = mDownSlopeSec * 60 * 60;
					if (downSlopeHours * 24 <= 100){
						downSlopeStr = (downSlopeHours * 24).toNumber() + Ui.loadResource(Rez.Strings.PercentPerDayLong);
					}
					else {
						downSlopeStr = (downSlopeHours).toNumber() + Ui.loadResource(Rez.Strings.PercentPerHourLong);
					}
				}
				dc.drawText(mCtrX, yPos, mFontType, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
			}
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, yPos, (mFontType > 0 ? mFontType - 1 : mFontType), Ui.loadResource(Rez.Strings.MoreDataNeeded), Gfx.TEXT_JUSTIFY_CENTER);		    	
			yPos += mFontHeight;
		}

		return yPos;
	}

	function doDownSlope() {
		if (mDownSlopeSec == null) { // Gte what we have nothing (ie, started) and we have something stored from previous run
			var downSlopeData = $.objectStoreGet("LAST_SLOPE_DATA", null);
			if (downSlopeData != null) {
				mDownSlopeSec = downSlopeData[0];
				mHistoryLastPos = downSlopeData[1];
				if (downSlopeData.size() == 3) {
					mSlopesSize = downSlopeData[2];
				}
			}
			else {
				mSlopeNeedsCalc = true;
			}
		}

		if (mDownSlopeSec == null || mSlopeNeedsCalc == true || mHistoryLastPos != mApp.mHistorySize) { // Only if we have change our data size or we haven't have a chance to calculate our slope yet
			// Calculate projected usage slope
			var downSlopeResult = $.downSlope();
            mDownSlopeSec = downSlopeResult[0];
            mSlopeNeedsCalc = downSlopeResult[1];
			mSlopesSize = downSlopeResult[2];
			mHistoryLastPos = mApp.mHistorySize;
			var downSlopeData = [mDownSlopeSec, mHistoryLastPos, mSlopesSize];
			$.objectStorePut("LAST_SLOPE_DATA", downSlopeData);
		}
	}

	function showMainPage(dc, lastChargeData) {
		var xPos = mCtrX * 2 * 3 / 5;
		var width = mCtrX * 2 / 18;
		var height = mCtrY * 2 * 17 / 20 / 5;
		var yPos = mCtrY * 2 * 2 / 20 + 4 * height;

	    var battery = Sys.getSystemStats().battery;
		var colorBat = getBatteryColor(battery);

		// Draw and color charge gauge
		dc.setPenWidth(1);
		dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
		for (var i = 0; i < 5; i++) {
			if (battery >= (i + 1) * 20) {
				dc.fillRectangle(xPos, yPos, width, height);
			}
			else if (battery < (i + 1) * 20 && battery > i * 20) {
				dc.drawRectangle(xPos, yPos, width, height);
				var fraction = (battery - i * 20) / 20;
				dc.fillRectangle(xPos, yPos + (1 - fraction) * height, width, height * fraction);
			}
			else {
				dc.drawRectangle(xPos, yPos, width, height);
			}
			yPos -= height + 2;
		}

		// Draw to the left of the gauge
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		yPos = mCtrY * 2 / 8;
		xPos -= 5;
		dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.BatteryLevel), Gfx.TEXT_JUSTIFY_RIGHT);
		yPos += mFontHeight * 2;
		dc.drawText(xPos, yPos, Gfx.FONT_NUMBER_MILD, battery.format("%0.1f") + "%", Gfx.TEXT_JUSTIFY_RIGHT);
		yPos += Gfx.getFontHeight(Gfx.FONT_NUMBER_MILD);
		dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.TimeRemaining), Gfx.TEXT_JUSTIFY_RIGHT);
		yPos += mFontHeight * 2;
		if (mSummaryProjection == true) {
			var downSlopeStr;
			if (mDownSlopeSec != null) {
				var downSlopeMin = mDownSlopeSec * 60;
				downSlopeStr = $.minToStr(battery / downSlopeMin, false);
				dc.drawText(xPos, yPos, mFontType, "~" + downSlopeStr, Gfx.TEXT_JUSTIFY_RIGHT);
			}
			else {
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_RIGHT);
			}
		}
		else {
			var remainingStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
            if (Sys.getSystemStats().charging == false) { // There won't be a since last charge if we're charging...
                if (lastChargeData != null ) {
                    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
                    var timeDiff = now - lastChargeData[0];
                    if (timeDiff != 0) { // Sanity check
                        var batAtLastCharge = $.stripMarkers(lastChargeData[1]) / 10.0;
                        if (batAtLastCharge > battery) { // Sanity check
                            var batDiff = batAtLastCharge - battery;
                            var dischargePerMin = batDiff * 60.0 / timeDiff;
                            remainingStr = $.minToStr(battery / dischargePerMin, false);

						}
					}
				}
			}
			dc.drawText(xPos, yPos, mFontType, "~" + remainingStr, Gfx.TEXT_JUSTIFY_RIGHT);
		}
		// Now to the right of the gauge
		xPos = mCtrX * 2 * 163 / 200;
		yPos = mCtrY * 2 * 5 / 16;

		if (lastChargeData != null) {
			var lastChargeHappened = $.minToStr((Time.now().value() - lastChargeData[TIMESTAMP]) / 60, false);
			dc.drawText(xPos, yPos, mFontType, lastChargeHappened, Gfx.TEXT_JUSTIFY_CENTER);
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_CENTER);
		}
		yPos += mFontHeight * 3 / 2;

		if (mSummaryProjection == true) {
			if (mDownSlopeSec != null) { 
				var downSlopeStr;
				var downSlopeHours = mDownSlopeSec * 60 * 60;
				if ((downSlopeHours * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
					downSlopeStr = (downSlopeHours * 24).format("%0.1f") + "\n" + Ui.loadResource(Rez.Strings.PercentPerDayLong);
				}
				else {
					downSlopeStr = (downSlopeHours).format("%0.2f") + "\n" + Ui.loadResource(Rez.Strings.PercentPerHourLong);
				}	
				dc.drawText(xPos, yPos, mFontType, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
			}
			else {
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_CENTER);
			}
		}
		else {
	        var dischargeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
            if (Sys.getSystemStats().charging == false) { // There won't be a since last charge if we're charging...
                if (lastChargeData != null ) {
                    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
                    var timeDiff = now - lastChargeData[0];
                    if (timeDiff != 0) { // Sanity check
                        var batAtLastCharge = $.stripMarkers(lastChargeData[1]) / 10.0;

                        if (batAtLastCharge > battery) { // Sanity check
                            var batDiff = batAtLastCharge - battery;
                            var dischargePerMin = batDiff * 60.0 / timeDiff;
							var downSlopeHours = dischargePerMin * 60;
							if ((downSlopeHours * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
								dischargeStr = (downSlopeHours * 24).format("%0.1f") + "\n" + Ui.loadResource(Rez.Strings.PercentPerDayLong);
							}
							else {
								dischargeStr = (downSlopeHours).format("%0.2f") + "\n" + Ui.loadResource(Rez.Strings.PercentPerHourLong);
							}	
						}
					}
				}
			}
			dc.drawText(xPos, yPos, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_CENTER);
		}
	}

	function showDataPage(dc, whichView, lastChargeData) {
	    var battery = Sys.getSystemStats().battery;
		var yPos = doHeader(dc, whichView, battery, false);

		yPos += mFontHeight / 4; // Give some room before displaying the charging stats

		//! Data section
		//DEBUG*/ logMessage(mNowData);
		//DEBUG*/ logMessage(mLastData);

		//! Bat usage since last view
		var batUsage;
		var timeDiff = 0;
		if (mNowData != null && mLastData != null) {
			var bat1 = $.stripMarkers(mNowData[BATTERY]);
			var bat2 = $.stripMarkers(mLastData[BATTERY]);
			batUsage = (bat1 - bat2) / 10.0;
			timeDiff = mNowData[TIMESTAMP] - mLastData[TIMESTAMP];
		}

		//DEBUG*/ logMessage("Bat usage: " + batUsage);
		//DEBUG*/ logMessage("Time diff: " + timeDiff);

		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SinceLastView), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		var dischargeRate;
		if (timeDiff > 0 && batUsage < 0) {
			dischargeRate = batUsage * 60 * 60 * (mViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
		}
		else {
			dischargeRate = 0.0f;
		}

		dischargeRate = (-dischargeRate).format("%0.3f") + (mViewScreen == SCREEN_DATA_HR ? Ui.loadResource(Rez.Strings.PercentPerHourLong) : Ui.loadResource(Rez.Strings.PercentPerDayLong));
		dc.drawText(mCtrX, yPos, mFontType, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		//DEBUG*/ logMessage("Discharge since last view: " + dischargeRate);

		//! Bat usage since last charge
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SinceLastCharge), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		if (mNowData != null && lastChargeData != null) {
			var bat1 = $.stripMarkers(mNowData[BATTERY]);
			var bat2 = $.stripMarkers(lastChargeData[BATTERY]);
			batUsage = (bat1 - bat2) / 10.0;
			timeDiff = mNowData[TIMESTAMP] - lastChargeData[TIMESTAMP];

			if (timeDiff != 0) {
				dischargeRate = batUsage * 60 * 60 * (mViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
			}
			else {
				dischargeRate = 0.0f;
			}

			dischargeRate = (-dischargeRate).format("%0.3f") + (mViewScreen == SCREEN_DATA_HR ? Ui.loadResource(Rez.Strings.PercentPerHourLong) : Ui.loadResource(Rez.Strings.PercentPerDayLong));
			dc.drawText(mCtrX, yPos, mFontType, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
			//DEBUG*/ logMessage("Discharge since last charge: " + dischargeRate);
		}
		else {
			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
			//DEBUG*/ logMessage("Discharge since last charge: N/A");
		}

		return yPos;
	}

	function showLastChargePage(dc, lastChargeData) {
	    var battery = Sys.getSystemStats().battery;
		var yPos = doHeader(dc, 2, battery, false); // We'll show the same header as SCREEN_DATA_HR

		//! How long for last charge?
		yPos += mFontHeight / 2; // Give some room before displaying the charging stats
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.LastCharge), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;
		if (lastChargeData && mStartedCharging == false) {
			var timestampStr = $.timestampToStr(lastChargeData[TIMESTAMP]);

			dc.drawText(mCtrX, yPos, mFontType,  timestampStr[0] + " " + timestampStr[1], Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.At) + " " + (lastChargeData[BATTERY] / 10.0).format("%0.1f") + "%" , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
		}
		else if (mStartedCharging == true) {
			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.Now) , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
		}
		else {
			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort) , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
		}

		return yPos;
	}

	function showMarkerPage(dc) {
	    var battery = Sys.getSystemStats().battery;
		var yPos;

		if (mMarkerData == null) {
			yPos = doHeader(dc, 2, battery, false); // We'll show the same header as SCREEN_DATA_HR
			yPos += mFontHeight / 2; // Give some room before displaying the charging stats
			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SetFirstMarker), Gfx.TEXT_JUSTIFY_CENTER);
			return yPos;
		}
		else if (mMarkerData.size() == 1) { // We only have one marker set, show it and say waiting for next marker
			yPos = doHeader(dc, 2, battery, false); // We'll show the same header as SCREEN_DATA_HR
			yPos += mFontHeight / 2; // Give some room before displaying the charging stats

			var timestampStr = $.timestampToStr(mMarkerData[0][TIMESTAMP]);
			var bat = $.stripMarkers(mMarkerData[0][BATTERY]) / 10.0;

			dc.drawText(mCtrX, yPos, mFontType,  timestampStr[0] + " " + timestampStr[1], Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.At) + " " + bat.format("%0.1f") + "%" , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SetSecondMarker), Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;
		}
		else { // We have both marker, show them as well as the discharge rate
			yPos = doHeader(dc, 2, battery, true); // We'll show just the battery
			yPos += mFontHeight / 2; // Give some room before displaying the charging stats
			var timestampStr = $.timestampToStr(mMarkerData[0][TIMESTAMP]);
			var bat1 = $.stripMarkers(mMarkerData[0][BATTERY]) / 10.0;

			dc.drawText(mCtrX, yPos, mFontType,  timestampStr[0] + " " + timestampStr[1], Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.At) + " " + bat1.format("%0.1f") + "%" , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			timestampStr = $.timestampToStr(mMarkerData[1][TIMESTAMP]);
			var bat2 = $.stripMarkers(mMarkerData[1][BATTERY]) / 10.0;

			dc.drawText(mCtrX, yPos, mFontType,  timestampStr[0] + " " + timestampStr[1], Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.At) + " " + bat2.format("%0.1f") + "%" , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			var batDiff = (bat1 - bat2).abs();
			var timeDiff = (mMarkerData[1][TIMESTAMP] - mMarkerData[0][TIMESTAMP]) / 60; // In minutes

			dc.drawText(mCtrX, yPos, mFontType, batDiff.format("%0.1f") + "% " + Ui.loadResource(Rez.Strings.In) + " " + $.minToStr(timeDiff, true) , Gfx.TEXT_JUSTIFY_CENTER);
			yPos += mFontHeight;

			if (timeDiff != 0) {
				var discharge = batDiff * 60.0 / timeDiff; // Discharge rate per hour
				var dischargeStr;
                if ((discharge * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
                    dischargeStr = (discharge * 24).format("%0.1f") + Ui.loadResource(Rez.Strings.PercentPerDayLong);
                }
                else {
                    dischargeStr = (discharge).format("%0.2f") + Ui.loadResource(Rez.Strings.PercentPerHourLong);
                }

		        dc.drawText(mCtrX, yPos, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
			}
		}

		return yPos;
	}


	function drawChart(dc, xy, whichView) {
		var startTime = Sys.getTimer();
		doHeader(dc, whichView, Sys.getSystemStats().battery, false);

    	var X1 = xy[0], X2 = xy[1], Y1 = xy[2], Y2 = xy[3];
		var yFrame = Y2 - Y1;// pixels available for level
		var xFrame = X2 - X1;// pixels available for time

		var timeLeftSecUNIX = null;

		//! draw y gridlines
		dc.setPenWidth(1);
		var yGridSteps = 0.1;
		for (var i = 0; i <= 1.05; i += yGridSteps) {
			if (i == 0 or i == 0.5 or i.toNumber() == 1) {
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			}
			else {
				dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
			}
			dc.drawLine(X1 - 10, Y2 - i * yFrame, X2 + 10, Y2 - i * yFrame);
		}

		if (mFullHistorySize == 0) {
			return; // Nothing to draw
		}

		var latestBattery = ($.stripMarkers(mFullHistory[(mFullHistorySize - 1) * mElementSize + BATTERY]) / 10.0).toNumber();

		if (mDownSlopeSec != null) {
			var timeLeftSec = (latestBattery / mDownSlopeSec).toNumber();
			timeLeftSecUNIX = timeLeftSec + mFullHistory[(mFullHistorySize - 1) * mElementSize + TIMESTAMP];
		}

		//! Graphical views
		var timeMostRecentPoint = mFullHistory[(mFullHistorySize - 1) * mElementSize + TIMESTAMP];
		var timeMostFuturePoint = (timeLeftSecUNIX != null && whichView == SCREEN_PROJECTION) ? timeLeftSecUNIX : timeMostRecentPoint;
		var timeLeastRecentPoint = (mGraphShowFull == true ? mFullHistory[0 + TIMESTAMP] : timeLastFullCharge(60 * 60 * 24)); // Try to show at least a day's worth of data if we're not showing full data

		var halfSpan = 0;
		var zoomLevel = [1, 2, 4, 8, 16, 32, 64, 128];
		var minimumTime = 60.0;
		if (whichView == SCREEN_HISTORY) {
			minimumTime /= zoomLevel[mGraphSizeChange];
			var span = timeMostRecentPoint - timeLeastRecentPoint;
			//DEBUG*/ logMessage("span is " + span + " timeMostRecentPoint is " + timeMostRecentPoint + " timeLeastRecentPoint is " + timeLeastRecentPoint + " zoom is " + mGraphSizeChange + " pan is " + mGraphOffsetChange);

			timeLeastRecentPoint = timeMostRecentPoint - span / zoomLevel[mGraphSizeChange];

			halfSpan = span / zoomLevel[mGraphSizeChange] / 2;
			timeMostRecentPoint -= halfSpan * mGraphOffsetChange;
			timeLeastRecentPoint -= halfSpan * mGraphOffsetChange;
		}

		var xHistoryInMin = (timeMostRecentPoint - timeLeastRecentPoint) / 60.0; // History time in minutes
		xHistoryInMin = MIN(MAX(xHistoryInMin, minimumTime), 60.0 * 24.0 * 30.0); // 30 days?

		var xFutureInMin = (timeMostFuturePoint - timeMostRecentPoint) / 60.0; // Future time in minutes
		xFutureInMin = MIN(MAX(xFutureInMin, minimumTime), (whichView == SCREEN_PROJECTION ? 60.0 * 24.0 * 30.0 : 0)); // 30 days?
		var xMaxInMin = xHistoryInMin + xFutureInMin; // Total time in minutes
		var xScaleMinPerPxl = xMaxInMin / xFrame; // in minutes per pixel
		var xNow; // position of now in the graph, equivalent to: pixels available for left part of chart, with history only (right part is future prediction)
		xNow = (xHistoryInMin / xScaleMinPerPxl).toNumber();

		//! Show which view mode is selected for the use of the PageNext/Previous and Swipe Left/Right (unless we have no data to work with)
		if (whichView == SCREEN_HISTORY && mDownSlopeSec != null && mDebug == 0) {
			var str;
			if (mSelectMode == ViewMode) {
				str = Ui.loadResource(Rez.Strings.ViewMode);
			}
			else if (mSelectMode == ZoomMode) {
				str = Ui.loadResource(Rez.Strings.ZoomMode) + " " + (mGraphShowFull ? Ui.loadResource(Rez.Strings.ZoomFull) : "") +  " x" + zoomLevel[mGraphSizeChange];
			}
			else {
				str = Ui.loadResource(Rez.Strings.PanMode);
			}

			var screenFormat = System.getDeviceSettings().screenShape;
			dc.drawText((screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : (30 * mCtrX * 2 / 240)), Y1 - mFontHeight - 1, mFontType, str, Gfx.TEXT_JUSTIFY_LEFT);
		}
		//! draw now position on axis
		dc.setPenWidth(2);
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		dc.drawLine(X1 + xNow, Y1 - mCtrY * 2 / 50, X1 + xNow, Y2);

		dc.setPenWidth(1);
		var lastPoint = [null, null];
		var Ymax = 100; //max value for battery

		//! draw history data
		var firstOutside = true;

		var steps = mFullHistorySize / xFrame / (mGraphSizeChange + 1);
		if (steps < 2) {
			steps = 1;
		}

		// First skip what's earlier than what we should show
		var i;
		for (i = mFullHistorySize - 1; i >= 0; i--) {
			if (mFullHistory[i * mElementSize + TIMESTAMP] <= timeMostRecentPoint) {
				if (i < mFullHistorySize - 1) {
					i++; // Get the first element outside so we can start our line from there, unless we're already at the top of the list
				}
				break;
			}
		}
		/*DEBUG*/ logMessage("Drawing graph with " + mFullHistorySize + " elements, steps is " + steps);
		for (; i >= 0; i -= steps) {
			//DEBUG*/ logMessage(i + " " + mFullHistory[i]);
			// End (closer to now)

			var timestamp = mFullHistory[i * mElementSize + TIMESTAMP];
			var bat = mFullHistory[i * mElementSize + BATTERY];
			var solar1 = mFullHistory[i * mElementSize + SOLAR];

			var batActivity = (bat & 0x1000 || (bat >= 2000 && bat < 4096) ? true : false); // Activity detected (0x1000 is its new marker and 2000 was its old marker)
			var batMarker = (bat & 0x2000 ? true : false); // Marker detected

			bat = $.stripMarkers(bat);

			for (var j = 1; j < steps && i - j >= 0; j++) {
				if (mIsSolar) {
					solar1 = MAX(solar1, mFullHistory[(i - j) * mElementSize + SOLAR]);
				}

				var bat1 = mFullHistory[(i - j) * mElementSize + BATTERY];
				bat = MAX(bat, $.stripMarkers(bat1));
				if (bat1 & 0x1000 || (bat1 >= 2000 && bat1 < 4096)) {
					batActivity = true;
				}
				if (bat1 & 0x2000) {
					batMarker = true;
				}
			}

			var timeEnd = timestamp;

			var dataTimeDistanceInMinEnd = ((timeMostRecentPoint - timeEnd) / 60).toNumber();

			var battery = (bat / 10.0).toNumber();
			var colorBat = getBatteryColor(battery);

			if (dataTimeDistanceInMinEnd > xHistoryInMin) {
				if (firstOutside == false) {
					continue; // This data point is outside of the graph view and it's not the first one being outside, ignore it
				}
				else {
					firstOutside = false; // Still draw it so we have a rectangle from the edge of the screen to the last point position
				}
			}

			var ySolar = null;
			if (mIsSolar) {
				var solar, dataHeightSolar;
				solar = solar1; //mFullHistory[i * mElementSize + SOLAR];
				if (solar != null) {
					dataHeightSolar = (solar * yFrame) / Ymax;
					ySolar = Y2 - dataHeightSolar;
				}
			}

			var dataHeightBat = (battery * yFrame) / Ymax;
			var yBat = Y2 - dataHeightBat;
			var dataTimeDistanceInPxl = dataTimeDistanceInMinEnd / xScaleMinPerPxl;
			var x = X1 + xNow - dataTimeDistanceInPxl;
			dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);

			if (lastPoint[0] != null) {
				dc.fillRectangle(x, yBat, lastPoint[0] - x + 1, Y2 - yBat);
			}
			if (ySolar && lastPoint[0] != null) {
				dc.setColor(Gfx.COLOR_DK_RED, Gfx.COLOR_TRANSPARENT);
				dc.drawLine(x, ySolar, lastPoint[0], lastPoint[1]);
			}

			if (batActivity == true && lastPoint[0] != null) { // We had an activity during that time span, draw the X axis in blue to say so
				dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
				dc.setPenWidth(5);
				dc.drawLine(x, Y2, lastPoint[0], Y2);
				dc.setPenWidth(1);
			}
			lastPoint = [x, ySolar];

			if (batMarker == true) {
				dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
				dc.setPenWidth(3);
				dc.drawLine(x, Y2, x, Y1);
				dc.setPenWidth(1);
			}

			batActivity = false; // Reset for next pass
			batMarker = false; // Reset for next pass

			if (mFullHistory[i * mElementSize + TIMESTAMP] < timeLeastRecentPoint) {
				break; // Stop if we've drawn the first point outside our graph area
			}
		}
		
		//! draw future estimation
		if (whichView == SCREEN_PROJECTION) {
			dc.setPenWidth(1);
			if (mDownSlopeSec != null){
				
				var pixelsAvail = xFrame - xNow;
				var timeDistanceMin = pixelsAvail * xScaleMinPerPxl;
				var xStart = X1 + xNow;
				var xEnd = xStart + pixelsAvail;
				var valueStart = latestBattery;
				var valueEnd = valueStart + -mDownSlopeSec * 60.0 * timeDistanceMin;
				if (valueEnd < 0){
					timeDistanceMin = valueStart / (mDownSlopeSec * 60.0);
					valueEnd = 0;
					xEnd = xStart + timeDistanceMin / xScaleMinPerPxl;
				}
				var yStart = Y2 - (valueStart * yFrame) / Ymax;
				var yEnd = Y2 - (valueEnd * yFrame) / Ymax;
			
				dc.setColor(COLOR_PROJECTION, Gfx.COLOR_TRANSPARENT);
				var triangle = [[xStart, yStart], [xEnd, yEnd], [xStart, yEnd], [xStart, yStart]];
				dc.fillPolygon(triangle);
			}
		}

		//! x-legend
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		var timeStr = $.minToStr(xHistoryInMin + (halfSpan * mGraphOffsetChange) / 60, false);
		var screenFormat = System.getDeviceSettings().screenShape;

		dc.drawText((screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : 26 * mCtrX * 2 / 240), Y2 + 2, (mFontType > 0 ? mFontType - 1 : 0),  "<-" + timeStr, Gfx.TEXT_JUSTIFY_LEFT);
		
		timeStr = $.minToStr(xFutureInMin + (halfSpan * mGraphOffsetChange) / 60, false);
		dc.drawText(mCtrX * 2 - (screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : (26 * mCtrX * 2 / 240)), Y2 + 2, (mFontType > 0 ? mFontType - 1 : 0), timeStr + "->", Gfx.TEXT_JUSTIFY_RIGHT);
		
		if (mDownSlopeSec != null){
			var timeLeftMin = (100.0 / (mDownSlopeSec * 60.0)).toNumber();
			timeStr = $.minToStr(timeLeftMin, false);
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, mCtrY * 2 - mFontHeight - mFontHeight / 3, (mFontType > 0 ? mFontType - 1 : 0), "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
		}

		var runTime = Sys.getTimer() - startTime;

		if ((whichView == SCREEN_HISTORY || whichView == SCREEN_PROJECTION) && mDebug >= 5) {
			dc.drawText(30 * mCtrX * 2 / 240, Y1 - mFontHeight - 1, mFontType, mHistoryArraySize + "/" + mFullHistorySize + "/" + mApp.mHistorySize + "/" + steps + "/" + runTime, Gfx.TEXT_JUSTIFY_LEFT);
		}
    }

	function showChargingPopup(dc) {
		//! Now add the 'popup' if the device is currently charging
		dc.setPenWidth(2);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		var screenFormat = System.getDeviceSettings().screenShape;

		dc.fillRoundedRectangle((screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : 10 * mCtrX * 2 / 240), mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * (screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : 10 * mCtrX * 2 / 240), 2 * (mFontHeight + mFontHeight / 2), 5);
		dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
		dc.drawRoundedRectangle((screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : 10 * mCtrX * 2 / 240), mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * (screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : 10 * mCtrX * 2 / 240), 2 * (mFontHeight + mFontHeight / 2), 5);
		var battery = Sys.getSystemStats().battery;
		dc.drawText(mCtrX, mCtrY - (mFontHeight + mFontHeight / 4), (mFontType < 4 ? mFontType + 1 : mFontType), Ui.loadResource(Rez.Strings.Charging) + " " + battery.format("%0.1f") + "%", Gfx.TEXT_JUSTIFY_CENTER);
		var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
		if (chargingData) {
			var batUsage = battery - (chargingData[BATTERY]) / 10.0;
			var timeDiff = Time.now().value() - chargingData[TIMESTAMP];

			//DEBUG*/ logMessage("Bat usage: " + batUsage);
			//DEBUG*/ logMessage("Time diff: " + timeDiff);
			var chargeRate;
			if (timeDiff > 0) {
				chargeRate = ((batUsage * 60 * 60 / timeDiff).format("%0.1f")).toString();
			}
			else {
				chargeRate = "0.0";
			}
			dc.drawText(mCtrX, mCtrY + mFontHeight / 8, (mFontType < 4 ? mFontType + 1 : mFontType), Ui.loadResource(Rez.Strings.Rate) + " " + chargeRate + Ui.loadResource(Rez.Strings.PercentPerHour), Gfx.TEXT_JUSTIFY_CENTER);
		}
	}

	function buildFullHistory() {
		var refreshedPrevious = false;

		if (mApp.getHistoryNeedsReload() == true || mFullHistory == null) { // Full refresh of the array
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
			var historyArraySize = historyArray.size();
			mHistoryArraySize = historyArraySize;

			mFullHistory = null; // Release memory before asking for more of the same thing
			mFullHistory = new [HISTORY_MAX * mElementSize * (historyArraySize == 0 ? 1 : historyArraySize)];
			mHistoryStartPos = 0;
			var j = 0;
			for (var index = 0; index < historyArraySize - 1; index++) {
				var previousHistory = $.objectStoreGet("HISTORY_" + historyArray[index], null);
				if (previousHistory != null) {
					for (var i = 0; i < HISTORY_MAX * mElementSize; i++, j++) {
						mFullHistory[j] = previousHistory[i];
					}
				}
			}

			mFullHistorySize = j / mElementSize;

			refreshedPrevious = true;
		}
		
		if (mApp.getFullHistoryNeedsRefesh() == true || mApp.getFullHistoryNeedsRefesh() == true) { // Only new data was added to mHistory, read them
			var i = mHistoryStartPos * mElementSize;
			var j = mFullHistorySize * mElementSize;
			for (; i < HISTORY_MAX * mElementSize && mApp.mHistory[i] != null; i++, j++) {
				mFullHistory[j] = mApp.mHistory[i];
			}

			mFullHistorySize = j / mElementSize;
			mHistoryStartPos = i / mElementSize;
		}

		mApp.setHistoryNeedsReload(false);
		mApp.setFullHistoryNeedsRefesh(false);

		return refreshedPrevious;
	}

	function getBatteryColor(battery) {
		var colorBat;

		if (battery >= 50) {
			colorBat = COLOR_BAT_OK;
		}
		else if (battery >= 30) {
			colorBat = COLOR_BAT_WARNING;
		}
		else if (battery >= 10) {
			colorBat = COLOR_BAT_LOW;
		}
		else {
			colorBat = COLOR_BAT_CRITICAL;
		}

		return colorBat;
	}


    function LastChargeData() {
		var bat2 = 0;

		if (mFullHistory != null) {
			for (var i = mFullHistorySize - 1; i >= 0; i--) {
				var bat1 = $.stripMarkers(mFullHistory[i * mElementSize + BATTERY]);
				if (bat2 > bat1) {
					i++; // We won't overflow as the first pass is always false with bat2 being 0
					var lastCharge = [mFullHistory[i * mElementSize + TIMESTAMP], bat2, mIsSolar ? mFullHistory[i * mElementSize + SOLAR] : null];
					$.objectStorePut("LAST_CHARGE_DATA", lastCharge);
					return lastCharge;
				}

				bat2 = bat1;
			}
		}

    	return null;
    }
    
    function timeLastFullCharge(minTime) {
		if (mFullHistory != null) { // Look through the full history
			for (var i = mFullHistorySize - 1; i > mTimeLastFullChargePos; i--) { // But starting where we left off before
				var bat = $.stripMarkers(mFullHistory[i * mElementSize + BATTERY]);
				if (bat >= 995) { // Watch rounds 99.5 as full so 99.5 is considered 'full'.
					if (minTime == null || mFullHistory[(mFullHistorySize - 1) * mElementSize + TIMESTAMP] - minTime >= mFullHistory[i * mElementSize + TIMESTAMP] ) { // If we ask for a minimum time to display, honor it, even if we saw a full charge already
						mTimeLastFullChargePos = mFullHistorySize - 1;
						mTimeLastFullChargeTime = mFullHistory[i * mElementSize + TIMESTAMP];
						return mTimeLastFullChargeTime;
					}
				}
			}
		}

    	return (mFullHistory != null ? mTimeLastFullChargeTime : mApp.mHistory[0 + TIMESTAMP]);
    }
    
	function MAX (val1, val2) {
		if (val1 > val2){
			return val1;
		}
		else {
			return val2;
		}
	}

	function MIN (val1, val2) {
		if (val1 < val2){
			return val1;
		}
		else {
			return val2;
		}
	}

	public function getVSelectMode() {
		return(mSelectMode);
	}

	public function getPanelIndex() {
		return(mPanelIndex);
	}

	public function getPanelSize() {
		return(mPanelSize);
	}
}