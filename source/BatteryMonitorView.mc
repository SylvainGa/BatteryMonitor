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
	var mElementSize;
	var mIsSolar;
	var mPanelOrder;
	var mPanelSize;
	var mPanelIndex;
	var mGraphSizeChange;
	var mGraphOffsetChange;
	var mCtrX, mCtrY;
	var mTimer;
	var mLastData;
	var mNowData;
	var mRefreshCount;
	var mFontType;
	var mFontHeight;
	var mSummaryMode;
	var mViewScreen;
	var mStartedCharging;
	var mSelectMode;
	/*DEBUG*/ var mHistoryArraySize;

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

		mRefreshCount = 0;
		mGraphSizeChange = 0;
		mGraphOffsetChange = 0;
		mSelectMode = ViewMode;

		//DEBUG*/ mDebugFont = 0;
		mTimer = new Timer.Timer();
		mTimer.start(method(:refreshTimer), 5000, true); // Check every 5 seconds

    	// add data to ensure most recent data is shown and no time delay on the graph.
		mStartedCharging = false;
		mHideChargingPopup = false;
		mLastData = $.objectStoreGet("LAST_VIEWED_DATA", null);
		mNowData = $.getData();
		
		$.analyzeAndStoreData([mNowData], 1);

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
		$.objectStorePut("LAST_VIEWED_DATA", mLastData);
		$.analyzeAndStoreData([mLastData], 1);
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

		mRefreshCount++;
		if (mRefreshCount == 12) { // Every minute, read a new set of data
			mNowData = $.getData();
			//DEBUG*/ logMessage("refreshTimer Read data " + mNowData);
			$.analyzeAndStoreData([mNowData], 1);
			mRefreshCount = 0;
		}
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
            Properties.setValue("PanelOrder", "1,2,3,4,5,6");
        }

		mPanelOrder = [1, 2, 3, 4, 5, 6];
		mPanelSize = 6;

        if (panelOrderStr != null) {
            var array = $.to_array(panelOrderStr, ",");
            if (array.size() > 1 && array.size() <= 6) {
                var i;
                for (i = 0; i < array.size(); i++) {
                    var val;
                    try {
                        val = array[i].toNumber();
                    }
                    catch (e) {
                        mPanelOrder = [1, 2, 3, 4, 5, 6];
                        i = 6;
                        break;
                    }

                    if (val != null && val > 0 && val <= 6) {
                        mPanelOrder[i] = val;
                    }
                    else {
                        mPanelOrder = [1, 2, 3, 4, 5, 6];
                        i = 6;
                        break;
                    }
                }

                mPanelSize = i;

                while (i < 6) {
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
			if (mViewScreen == SCREEN_HISTORY) {
				mSelectMode += 1;
				if (mSelectMode > PanMode) {
					mSelectMode = ViewMode;
				}
				/*DEBUG*/ logMessage("Changing Select mode to " + mSelectMode);
			}
		}
		else {
			if (newIndex != mPanelIndex) {
				mGraphSizeChange = 0; // If we changed panel, reset zoom of graphic view
				mGraphOffsetChange = 0; // and offset
				mSelectMode = ViewMode; // and our view mode in the history view
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
			}
			else if (mGraphSizeChange > 5) {
				mGraphSizeChange = 5;
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
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);		
        dc.clear();

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
	
		/*DEBUG*/var startTime = Sys.getTimer();

       	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);	

		//DEBUG*/ var fonts = [Gfx.FONT_XTINY, Gfx.FONT_TINY, Gfx.FONT_SMALL, Gfx.FONT_MEDIUM, Gfx.FONT_LARGE]; mFontType = fonts[mDebugFont]; dc.drawText(0, mCtrY, mFontType, mDebugFont, Gfx.TEXT_JUSTIFY_LEFT);

		if (buildFullHistory() == true) {
			Ui.requestUpdate(); // Time consuming, stop now and ask for another time slice
			return;
		}

		//! Calculate projected usage slope
		var downSlopeSec = $.downSlope();
		var lastChargeData = LastChargeData();
		switch (mViewScreen) {
			case SCREEN_DATA_MAIN:
				showMainPage(dc, downSlopeSec, lastChargeData);
				break;
				
			case SCREEN_DATA_HR:
				showDataPage(dc, SCREEN_DATA_HR, downSlopeSec, lastChargeData);
				break;

			case SCREEN_DATA_DAY:
				showDataPage(dc, SCREEN_DATA_DAY, downSlopeSec, lastChargeData);
				break;

			case SCREEN_LAST_CHARGE:
				showLastChargePage(dc, downSlopeSec, lastChargeData);
				break;
				
			case SCREEN_HISTORY:
				drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_HISTORY, downSlopeSec);
				break;

			case SCREEN_PROJECTION:
				drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_PROJECTION, downSlopeSec);
				break;
		}

		// If charging, show its popup over any screen
		if (System.getSystemStats().charging) {
			if (mStartedCharging == false) {
				mStartedCharging = true;
				$.analyzeAndStoreData([$.getData()], 1);
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

		var endTime = Sys.getTimer();

		/*DEBUG*/ logMessage("onUpdate for " + mViewScreen + " took " + (endTime - startTime) + "msec");
    }

	function doHeader(dc, whichView, battery, downSlopeSec) {
		//! Display current charge level with the appropriate color
		var colorBat = $.getBatteryColor(battery);
		dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
		dc.drawText(mCtrX, 20 * mCtrY * 2 / 240, Gfx.FONT_NUMBER_MILD, battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
    	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);

		var scale = mCtrY * 2.0 / 240.0; // 240 was the default resolution of the watch used at the time this widget was created
		var yPos = 35 * scale;
		if (downSlopeSec != null) {
			var downSlopeStr;
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			if (whichView == SCREEN_DATA_HR) {
				dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.Remaining), Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				if (mStartedCharging == true) {
					downSlopeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
				}
				else {
					var downSlopeMin = downSlopeSec * 60;
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
					var downSlopeHours = downSlopeSec * 60 * 60;
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

		return (yPos);
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
			var batUsage = battery - (chargingData[BATTERY]).toFloat() / 10.0;
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

	function showMainPage(dc, downSlopeSec, lastChargeData) {
		// Draw and color charge gauge
		var xPos = mCtrX * 2 * 3 / 5;
		var width = mCtrX * 2 / 18;
		var height = mCtrY * 2 * 17 / 20 / 5;
		var yPos = mCtrY * 2 * 2 / 20 + 4 * height;

	    var battery = Sys.getSystemStats().battery;
		var colorBat = $.getBatteryColor(battery);

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
		var downSlopeStr;
		if (downSlopeSec != null) {
			var downSlopeMin = downSlopeSec * 60;
			downSlopeStr = $.minToStr(battery / downSlopeMin, false);
			dc.drawText(xPos, yPos, mFontType, "~" + downSlopeStr, Gfx.TEXT_JUSTIFY_RIGHT);
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_RIGHT);
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

		if (downSlopeSec != null) { 
			var downSlopeHours = downSlopeSec * 60 * 60;
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

	function showDataPage(dc, whichView, downSlopeSec, lastChargeData) {
	    var battery = Sys.getSystemStats().battery;
		var yPos = doHeader(dc, whichView, battery, downSlopeSec );

		yPos += mFontHeight / 4; // Give some room before displaying the charging stats

		//! Data section
		//DEBUG*/ logMessage(mNowData);
		//DEBUG*/ logMessage(mLastData);

		//! Bat usage since last view
		var batUsage;
		var timeDiff = 0;
		if (mNowData != null && mLastData != null) {
			var bat1 = mNowData[BATTERY];
			if (bat1 >= 2000) {
				bat1 -= 2000;
			}
			var bat2 = mLastData[BATTERY];
			if (bat2 >= 2000) {
				bat2 -= 2000;
			}
			batUsage = (bat1 - bat2).toFloat() / 10.0;
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

		dischargeRate = dischargeRate.abs().format("%0.3f") + (mViewScreen == SCREEN_DATA_HR ? Ui.loadResource(Rez.Strings.PercentPerHourLong) : Ui.loadResource(Rez.Strings.PercentPerDayLong));
		dc.drawText(mCtrX, yPos, mFontType, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		//DEBUG*/ logMessage("Discharge since last view: " + dischargeRate);

		//! Bat usage since last charge
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SinceLastCharge), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		if (mNowData != null && lastChargeData != null) {
			var bat1 = mNowData[BATTERY];
			if (bat1 >= 2000) {
				bat1 -= 2000;
			}
			var bat2 = lastChargeData[BATTERY];
			if (bat2 >= 2000) {
				bat2 -= 2000;
			}
			batUsage = (bat1 - bat2).toFloat() / 10.0;
			timeDiff = mNowData[TIMESTAMP] - lastChargeData[TIMESTAMP];

			if (timeDiff != 0) {
				dischargeRate = batUsage * 60 * 60 * (mViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
			}
			else {
				dischargeRate = 0.0f;
			}

			dischargeRate = dischargeRate.abs().format("%0.3f") + (mViewScreen == SCREEN_DATA_HR ? Ui.loadResource(Rez.Strings.PercentPerHourLong) : Ui.loadResource(Rez.Strings.PercentPerDayLong));
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

	function showLastChargePage(dc, downSlopeSec, lastChargeData) {
	    var battery = Sys.getSystemStats().battery;
		var yPos = doHeader(dc, 2, battery, downSlopeSec); // We"ll show the same header as SCREEN_DATA_HR

		//! How long for last charge?
		yPos += mFontHeight / 2; // Give some room before displaying the charging stats
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.LastCharge), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;
		if (lastChargeData && mStartedCharging == false) {
			var timeMoment = new Time.Moment(lastChargeData[TIMESTAMP]);
			var date = Time.Gregorian.info(timeMoment, Time.FORMAT_MEDIUM);

			// Format time accoring to 24/12 hour format
			var timeStr;
			if (Sys.getDeviceSettings().is24Hour) {
				timeStr = Lang.format("$1$h$2$", [date.hour.format("%2d"), date.min.format("%02d")]);
			}
			else {
				var ampm = "am";
				var hours12 = date.hour;

				if (date.hour == 0) {
					hours12 = 12;
				}
				else if (date.hour > 12) {
					ampm = "pm";
					hours12 -= 12;
				}

				timeStr = Lang.format("$1$:$2$$3$", [hours12.format("%2d"), date.min.format("%02d"), ampm]);
			}

			// Format the date according to the language file
			var dateFormat = Ui.loadResource(Rez.Strings.MediumDateFormat);
			var dateStr = Lang.format(dateFormat, [date.day_of_week, date.day, date.month]);

			dc.drawText(mCtrX, yPos, mFontType,  dateStr + " " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
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

	function drawChart(dc, xy, whichView, downSlopeSec) {
		doHeader(dc, whichView, Sys.getSystemStats().battery, downSlopeSec );

    	var X1 = xy[0], X2 = xy[1], Y1 = xy[2], Y2 = xy[3];
		var timeLeftSecUNIX = null;

		if (mFullHistorySize == 0) {
			return; // Nothing to draw
		}

		var latestBattery = mFullHistory[(mFullHistorySize - 1) * mElementSize + BATTERY];
		if (latestBattery >= 2000) {
			latestBattery -= 2000;
		}
		latestBattery = (latestBattery.toFloat() / 10.0).toNumber();

		if (downSlopeSec != null) {
			var timeLeftSec = (latestBattery / downSlopeSec).toNumber();
			timeLeftSecUNIX = timeLeftSec + mFullHistory[(mFullHistorySize - 1) * mElementSize + TIMESTAMP];
		}

		//! Graphical views
		var yFrame = Y2 - Y1;// pixels available for level
		var xFrame = X2 - X1;// pixels available for time
		var timeMostRecentPoint = mFullHistory[(mFullHistorySize - 1) * mElementSize + TIMESTAMP];
		var timeMostFuturePoint = (timeLeftSecUNIX != null && whichView == SCREEN_PROJECTION) ? timeLeftSecUNIX : timeMostRecentPoint;
		var timeLeastRecentPoint = timeLastFullCharge(60 * 60 * 24); // Try to show at least a day's worth of data

		var halfSpan = 0;
		if (whichView == SCREEN_HISTORY) {
			var zoomLevel = [1, 2, 4, 8, 16, 32];
			var span = timeMostRecentPoint - timeLeastRecentPoint;
			/*DEBUG*/ logMessage("span is " + span + " timeMostRecentPoint is " + timeMostRecentPoint + " timeLeastRecentPoint is " + timeLeastRecentPoint + " zoom is " + mGraphSizeChange + " pan is " + mGraphOffsetChange);

			timeLeastRecentPoint = timeMostRecentPoint - span / zoomLevel[mGraphSizeChange];

			halfSpan = span / zoomLevel[mGraphSizeChange] / 2;
			timeMostRecentPoint -= halfSpan * mGraphOffsetChange;
			timeLeastRecentPoint -= halfSpan * mGraphOffsetChange;
		}

		var xHistoryInMin = (timeMostRecentPoint - timeLeastRecentPoint).toFloat() / 60.0; // History time in minutes
		xHistoryInMin = MIN(MAX(xHistoryInMin, 60.0), 60.0 * 24.0 * 30.0); // 30 days?

		// if (whichView == SCREEN_HISTORY) {
		// 	var zoomLevel = [1, 2, 4, 8, 16, 32];
		// 	xHistoryInMin /= zoomLevel[mGraphSizeChange];
		// }

		var xFutureInMin = (timeMostFuturePoint - timeMostRecentPoint).toFloat() / 60.0; // Future time in minutes
		xFutureInMin = MIN(MAX(xFutureInMin, 60.0), (whichView == SCREEN_PROJECTION ? 60.0 * 24.0 * 30.0 : 0)); // 30 days?
		var xMaxInMin = xHistoryInMin + xFutureInMin; // Total time in minutes
		var xScaleMinPerPxl = xMaxInMin / xFrame; // in minutes per pixel
		var xNow; // position of now in the graph, equivalent to: pixels available for left part of chart, with history only (right part is future prediction)
		xNow = (xHistoryInMin / xScaleMinPerPxl).toNumber();

		//! Show which view mode is selected for the use of the PageNext/Previous and Swipe Left/Right 
		if (whichView == SCREEN_HISTORY) {
			var str;
			if (mSelectMode == ViewMode) {
				str = Ui.loadResource(Rez.Strings.ViewMode);
			}
			else if (mSelectMode == ZoomMode) {
				str = Ui.loadResource(Rez.Strings.ZoomMode);
			}
			else {
				str = Ui.loadResource(Rez.Strings.PanMode);
			}

			var screenFormat = System.getDeviceSettings().screenShape;
			dc.drawText((screenFormat == System.SCREEN_SHAPE_RECTANGLE ? 5 : (30 * mCtrX * 2 / 240)), Y1 - mFontHeight - 3, mFontType, str, Gfx.TEXT_JUSTIFY_LEFT);
		}
		//! draw now position on axis
		dc.setPenWidth(2);
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		dc.drawLine(X1 + xNow, Y1 - mCtrY * 2 / 50, X1 + xNow, Y2);

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

		dc.setPenWidth(1);
		var lastPoint = [null, null];
		var Ymax = 100; //max value for battery

		//! draw history data
		var firstOutside = true;

		var steps = mFullHistorySize / xFrame;
		if (steps < 2) {
			steps = 1;
		}
		/*DEBUG*/ logMessage("Drawing graph with " + mFullHistorySize + " elements, steps is " + steps);
		/*DEBUG*/ if (whichView == SCREEN_PROJECTION) { dc.drawText(30 * mCtrX * 2 / 240, Y1 - mFontHeight - 3, mFontType, mHistoryArraySize + "/" + mFullHistorySize + "/" + mApp.mHistorySize + "/" + steps + "/" + gSlopesSize, Gfx.TEXT_JUSTIFY_LEFT); }

		for (var i = mFullHistorySize - 1/*, lastDataTime = mFullHistory[i * mElementSize + TIMESTAMP]*/; i >= 0; i -= steps) {
			//DEBUG*/ logMessage(i + " " + mFullHistory[i]);
			// End (closer to now)

			var timestamp = mFullHistory[i * mElementSize + TIMESTAMP];
			var bat = mFullHistory[i * mElementSize + BATTERY];
			var solar1 = mFullHistory[i * mElementSize + SOLAR];

			for (var j = 1; j < steps && i - j >= 0; j++) {
				bat = MAX(bat, mFullHistory[(i - j) * mElementSize + BATTERY]);
				if (mIsSolar) {
					solar1 = MAX(solar1, mFullHistory[(i - j) * mElementSize + SOLAR]);
				}
			}

			var timeEnd = timestamp; //mFullHistory[i * mElementSize + TIMESTAMP];

			// if (i != mFullHistorySize - 1 && lastDataTime - timeEnd < xScaleMinPerPxl * 60 / 5) {
			// 	/*DEBUG*/ skipped++;
			// 	continue;
			// }
			// lastDataTime = timeEnd;

			var dataTimeDistanceInMinEnd = ((timeMostRecentPoint - timeEnd) / 60).toNumber();

			var batActivity = false;
			var battery = bat; //mFullHistory[i * mElementSize + BATTERY];
			if (battery >= 2000) {
				battery -= 2000;
				batActivity = true;
			}
			battery = (battery.toFloat() / 10.0).toNumber();
			var colorBat = $.getBatteryColor(battery);

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
		}
		
		//! draw future estimation
		if (whichView == SCREEN_PROJECTION) {
			dc.setPenWidth(1);
			if (downSlopeSec != null){
				
				var pixelsAvail = xFrame - xNow;
				var timeDistanceMin = pixelsAvail * xScaleMinPerPxl;
				var xStart = X1 + xNow;
				var xEnd = xStart + pixelsAvail;
				var valueStart = latestBattery;
				var valueEnd = valueStart + -downSlopeSec * 60.0 * timeDistanceMin;
				if (valueEnd < 0){
					timeDistanceMin = valueStart / (downSlopeSec * 60.0);
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
		
		if (downSlopeSec != null){
			var timeLeftMin = (100.0 / (downSlopeSec * 60.0)).toNumber();
			timeStr = $.minToStr(timeLeftMin, false);
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, mCtrY * 2 - mFontHeight - mFontHeight / 3, (mFontType > 0 ? mFontType - 1 : 0), "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
		}
    }

	function buildFullHistory() {
		var refreshedPrevious = false;

		if (mApp.getHistoryNeedsReload() == true || mFullHistory == null) { // Full refresh of the array
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
			var historyArraySize = historyArray.size();
			/*DEBUG*/ mHistoryArraySize = historyArraySize;

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

    function LastChargeData() {
		var bat2 = 1000;

		if (mFullHistory != null) { // Ran out of data in our current history, look through our previous history array
			for (var i = mFullHistorySize - 1; i > 0; i--) {
				var bat1 = mFullHistory[i * mElementSize + BATTERY];
				if (bat1 >= 2000) {
					bat1 -= 2000;
				}

				if (bat1 > bat2) {
					return [mFullHistory[i * mElementSize + TIMESTAMP], bat1, mIsSolar ? mFullHistory[i * mElementSize + SOLAR] : null];
				}

				bat2 = bat1;
			}
		}

    	return null;
    }
    
    function timeLastFullCharge(minTime) {
		if (mFullHistory != null) { // Ran out of data in our current history, look through our previous history array
			for (var i = mFullHistorySize - 1; i > 0; i--) {
				var bat = mFullHistory[i * mElementSize + BATTERY];
				if (bat >= 2000) {
					bat -= 2000;
				}

				if (bat == 1000) {
					if (minTime == null || mFullHistory[(mApp.mHistorySize - 1) * mElementSize + TIMESTAMP] - minTime >= mFullHistory[i * mElementSize + TIMESTAMP] ) { // If we ask for a minimum time to display, honor it, even if we saw a full charge already
						return mFullHistory[i * mElementSize + TIMESTAMP];
					}
				}
			}
		}

    	return (mFullHistory != null ? mFullHistory[0 + TIMESTAMP] : mApp.mHistory[0 + TIMESTAMP]);
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