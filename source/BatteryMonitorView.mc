using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Math;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;
using Toybox.Application.Properties;

class BatteryMonitorView extends Ui.View {
	var mPanelOrder;
	var mPanelSize;
	var mPanelIndex;
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

    function initialize() {
        View.initialize();
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
		objectStorePut("VIEW_RUNNING", true);

		mTimer = new Timer.Timer();
		mTimer.start(method(:refreshTimer), 5000, true); // Check every five second
    	
    	// add data to ensure most recent data is shown and no time delay on the graph.
		mStartedCharging = false;
		mRefreshCount = 0;
		mLastData = objectStoreGet("LAST_VIEWED_DATA", null);
		mNowData = getData();
		analyzeAndStoreData(mNowData);

		onSettingsChanged();
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.

    function onHide() {
		objectStorePut("VIEW_RUNNING", false);

		if (mTimer) {
			mTimer.stop();
		}
		mTimer = null;
		mLastData = getData();
		objectStorePut("LAST_VIEWED_DATA", mLastData);
		analyzeAndStoreData(mLastData);
	}

	function onEnterSleep() {
		// Code to run when the app is about to be suspended, e.g., during USB connection
		if (System.getSystemStats().charging) {
			// Optionally store the charging state
		}
	}

	function onExitSleep() {
		// Code to run when the app resumes
		if (System.getSystemStats().charging) {
			// Handle charging state
		}
	}

	function refreshTimer() as Void {
		if (System.getSystemStats().charging) {
			// Update UI, log charging status, etc.
		}

		mRefreshCount++;
		if (mRefreshCount == 12) { // Every minute, read a new set of data
			mNowData = getData();
			//DEBUG*/ logMessage("Adding data " + mNowData);
			analyzeAndStoreData(mNowData);
			mRefreshCount = 0;
		}
		Ui.requestUpdate();
	}

    // Load your resources here
    function onLayout(dc) {
    	mCtrX = dc.getWidth() / 2;
    	mCtrY = dc.getHeight() / 2; 

		var fonts = [Gfx.FONT_XTINY, Gfx.FONT_TINY, Gfx.FONT_SMALL, Gfx.FONT_MEDIUM, Gfx.FONT_LARGE];

		// The right font is about 10% of the screen size
		for (var i = 0; i < fonts.size(); i++) {
			var fontHeight = Gfx.getFontHeight(fonts[i]);
			if (dc.getHeight() / fontHeight < 11) {
				mFontType = fonts[i];
				break;
			}
		}

		if (mFontType == null) {
			mFontType = Gfx.FONT_LARGE;
		}

		mFontHeight = Gfx.getFontHeight(mFontType);
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
            Properties.setValue("PanelOrder", "1,2,3,4,5");
        }

		mPanelOrder = [1, 2, 3, 4, 5];
		mPanelSize = 5;

        if (panelOrderStr != null) {
            var array = to_array(panelOrderStr, ",");
            if (array.size() > 1 && array.size() <= 5) {
                var i;
                for (i = 0; i < array.size(); i++) {
                    var val;
                    try {
                        val = array[i].toNumber();
                    }
                    catch (e) {
                        mPanelOrder = [1, 2, 3, 4, 5];
                        i = 5;
                        break;
                    }

                    if (val != null && val > 0 && val <= 5) {
                        mPanelOrder[i] = val;
                    }
                    else {
                        mPanelOrder = [1, 2, 3, 4, 5];
                        i = 5;
                        break;
                    }
                }

                mPanelSize = i;

                while (i < 5) {
                    mPanelOrder[i] = null;
                    i++;
                }
            }
        }

		mPanelIndex = 0;
		mViewScreen = mPanelOrder[0];
    }

	function onReceive(newIndex) {
		mPanelIndex = newIndex;
		mViewScreen = mPanelOrder[mPanelIndex];
		Ui.requestUpdate();
	}

    // Update the view
    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);		
        dc.clear();

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
        
       	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);	
        
		var history = objectStoreGet("HISTORY_KEY", null);
		
		//DEBUG*/ Sys.print("["); for (var i = 0; i < history.size(); i++) { Sys.print(history[i]); if (i < history.size() - 1) { Sys.print(","); } } Sys.println("]");
		//DEBUG*/ for (var i = 0; i < history.size(); i++) { var timeStartMoment = new Time.Moment(history[i][TIMESTAMP]); var timeStartInfo = Gregorian.info(timeStartMoment, Time.FORMAT_MEDIUM); Sys.println("At " + timeStartInfo.hour + "h" + timeStartInfo.min + "m - Batterie " + history[i][BATTERY].toFloat() / 1000.0 + "%" + (history[i].size() == 3 ? " - Solar " + history[i][SOLAR] + "%" : "")); } Sys.println("");

		if (!(history instanceof Toybox.Lang.Array)) {
			var battery = Sys.getSystemStats().battery;
			dc.drawText(mCtrX, mCtrY, (mFontType < 4 ? mFontType + 1 : mFontType), Ui.loadResource(Rez.Strings.NoRecordedData) + battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
		}
		else {
			history = history.reverse(); // Data is added at the end and we need it at the top of the array for efficiency when processing so reverse it here

			//! Calculate projected usage slope
			var downSlopeSec = downSlope(history);
			var lastChargeData = LastChargeData(history);
			var nowData = history[0];
			switch (mViewScreen) {
				case SCREEN_DATA_MAIN:
					showMainPage(dc, downSlopeSec, lastChargeData, nowData);
					break;
					
				case SCREEN_DATA_HR:
					showDataPage(dc, SCREEN_DATA_HR, downSlopeSec, lastChargeData, nowData);
					break;

				case SCREEN_DATA_DAY:
					showDataPage(dc, SCREEN_DATA_DAY, downSlopeSec, lastChargeData, nowData);
					break;

				case SCREEN_HISTORY:
					drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_HISTORY, downSlopeSec, history);
					break;

				case SCREEN_PROJECTION:
					drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], SCREEN_PROJECTION, downSlopeSec, history);
					break;
			}
		}

		// If charging, show its popup over any screen
		if (System.getSystemStats().charging) {
			if (mStartedCharging == false) {
				mStartedCharging = true;
				analyzeAndStoreData(getData());
			}
			showChargingPopup(dc);
		}
		else {
				mStartedCharging = false;
		}
    }

	function doHeader(dc, whichView, battery, downSlopeSec) {
		//! Display current charge level with the appropriate color
		var colorBat = getBatteryColor(battery);
		dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
		dc.drawText(mCtrX, 20 * mCtrY * 2 / 240, Gfx.FONT_NUMBER_MILD, battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
    	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);

		var scale = mCtrY * 2.0 / 240.0; // 240 was the default resolution of the watch used at the time this widget was created
		var yPos = 35 * scale;
		if (downSlopeSec != null) {
			var downSlopeStr;
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			if (whichView == SCREEN_DATA_HR) {
				var downSlopeMin = downSlopeSec * 60;
				downSlopeStr = minToStr(battery / downSlopeMin, true);
				dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.Remaining), Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				dc.drawText(mCtrX, yPos, mFontType, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
			}
			else if (whichView == SCREEN_DATA_DAY) {
				var downSlopeHours = downSlopeSec * 60 * 60;
				if (downSlopeHours * 24 <= 100){
					downSlopeStr = (downSlopeHours * 24).toNumber() + Ui.loadResource(Rez.Strings.PercentPerDayLong);
				}
				else {
					downSlopeStr = (downSlopeHours).toNumber() + Ui.loadResource(Rez.Strings.PercentPerHourLong);
				}	
				dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.Discharging), Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				dc.drawText(mCtrX, yPos, mFontType, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
			}
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, yPos, (mFontType > 0 ? mFontType - 1 : mFontType), Ui.loadResource(Rez.Strings.MoreDataNeeded), Gfx.TEXT_JUSTIFY_CENTER);		    	
		}
		yPos += mFontHeight;

		return (yPos);
	}

	function showChargingPopup(dc) {
		//! Now add the 'popup' if the device is currently charging
		dc.setPenWidth(2);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillRoundedRectangle(27, mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * 27, 2 * (mFontHeight + mFontHeight / 2), 5);
		dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
		dc.drawRoundedRectangle(27, mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * 27, 2 * (mFontHeight + mFontHeight / 2), 5);
		var battery = Sys.getSystemStats().battery;
		dc.drawText(mCtrX, mCtrY - (mFontHeight + mFontHeight / 4), (mFontType < 4 ? mFontType + 1 : mFontType), Ui.loadResource(Rez.Strings.Charging) + " " + battery.format("%0.1f") + "%", Gfx.TEXT_JUSTIFY_CENTER);
		var chargingData = objectStoreGet("STARTED_CHARGING_DATA", null);
		if (chargingData) {
			var batUsage = battery - (chargingData[BATTERY]).toFloat() / 1000.0;
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

	function showMainPage(dc, downSlopeSec, lastChargeData, nowData) {
		// Draw and color charge gauge
		var xPos = mCtrX * 2 * 3 / 5;
		var width = mCtrX * 2 / 18;
		var height = mCtrY * 2 * 17 / 20 / 5;
		var yPos = mCtrY * 2 * 2 / 20 + 4 * height;

	    var battery = Sys.getSystemStats().battery;
		var colorBat = getBatteryColor(battery);

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
			downSlopeStr = minToStr(battery / downSlopeMin, false);
			dc.drawText(xPos, yPos, mFontType, "~" + downSlopeStr, Gfx.TEXT_JUSTIFY_RIGHT);
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(xPos, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_RIGHT);
		}

		// Now to the right of the gauge
		xPos = mCtrX * 2 * 4 / 5;
		yPos = mCtrY * 2 * 5 / 16;

		if (lastChargeData != null) {
			var lastChargeHappened = minToStr((Time.now().value() - lastChargeData[TIMESTAMP]) / 60, false);
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

	function showDataPage(dc, whichView, downSlopeSec, lastChargeData, nowData) {
	    var battery = Sys.getSystemStats().battery;
		var yPos = doHeader(dc, whichView, battery, downSlopeSec );

		//! Data section
		//DEBUG*/ logMessage(mNowData);
		//DEBUG*/ logMessage(mLastData);

		//! Bat usage since last view
		var batUsage;
		var timeDiff = 0;
		if (mNowData && mLastData) {
			batUsage = (mNowData[BATTERY] - mLastData[BATTERY]).toFloat() / 1000.0;
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

		//DEBUG*/ logMessage("Discharge since last view: " + dischargeRate);

		//! Bat usage since last charge
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.SinceLastCharge), Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		if (lastChargeData != null) {
			batUsage = (nowData[BATTERY] - lastChargeData[BATTERY]).toFloat() / 1000.0;
			timeDiff = nowData[TIMESTAMP] - lastChargeData[TIMESTAMP];

			if (timeDiff != 0) {
				dischargeRate = batUsage * 60 * 60 * (mViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
			}
			else {
				dischargeRate = 0.0f;
			}

			dischargeRate = dischargeRate.abs().format("%0.3f") + (mViewScreen == SCREEN_DATA_HR ? Ui.loadResource(Rez.Strings.PercentPerHourLong) : Ui.loadResource(Rez.Strings.PercentPerDayLong));
			dc.drawText(mCtrX, yPos, mFontType, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
			//DEBUG*/ logMessage("Discharge since last charge: " + dischargeRate);
		}
		else {
			dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.NotAvailableShort), Gfx.TEXT_JUSTIFY_CENTER);
			//DEBUG*/ logMessage("Discharge since last charge: N/A");
		}

		//! How long for last charge?
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, mFontType, Ui.loadResource(Rez.Strings.LastChargeHappened), Gfx.TEXT_JUSTIFY_CENTER);
		var lastChargeHappened;
		if (lastChargeData) {
			lastChargeHappened = Ui.loadResource(Rez.Strings.LastChargeHappenedPrefix) + minToStr((Time.now().value() - lastChargeData[TIMESTAMP]) / 60, false) + Ui.loadResource(Rez.Strings.LastChargeHappenedSuffix);
		}
		else {
			lastChargeHappened = Ui.loadResource(Rez.Strings.NotAvailableShort);
		}
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, mFontType, lastChargeHappened, Gfx.TEXT_JUSTIFY_CENTER);

		return yPos;
	}

	function drawChart(dc, xy, whichView, downSlopeSec, chartData) {
		doHeader(dc, whichView, Sys.getSystemStats().battery, downSlopeSec );

    	var X1 = xy[0], X2 = xy[1], Y1 = xy[2], Y2 = xy[3];
		var timeLeftSecUNIX = null;
		if (downSlopeSec != null) {
			var battery = (chartData[0][BATTERY].toFloat() / 1000.0).toNumber();
			var timeLeftSec = (battery / downSlopeSec).toNumber();
			timeLeftSecUNIX = timeLeftSec + chartData[0][TIMESTAMP];
		}

		//! Graphical views
		var Yframe = Y2 - Y1;// pixels available for level
		var Xframe = X2 - X1;// pixels available for time
		var timeMostRecentPoint = chartData[0][TIMESTAMP];
		var timeMostFuturePoint = (timeLeftSecUNIX != null && whichView == SCREEN_PROJECTION) ? timeLeftSecUNIX : timeMostRecentPoint;
		var timeLeastRecentPoint = timeLastFullCharge(chartData, 60 * 60 * 24); // Try to show at least a day's worth of data
		var xHistoryInMin = (timeMostRecentPoint - timeLeastRecentPoint).toFloat() / 60.0; // History time in minutes
		xHistoryInMin = MIN(MAX(xHistoryInMin, 60.0), 60.0 * 25.0 * 30.0);
		var xFutureInMin = (timeMostFuturePoint - timeMostRecentPoint).toFloat() / 60.0; // Future time in minutes
		xFutureInMin = MIN(MAX(xFutureInMin, 60.0), (whichView == SCREEN_PROJECTION ? 60.0 * 25.0 * 30.0 : 0));
		var XmaxInMin = xHistoryInMin + xFutureInMin; // Total time in minutes
		var XscaleMinPerPxl = XmaxInMin / Xframe; // in minutes per pixel
		var Xnow; // position of now in the graph, equivalent to: pixels available for left part of chart, with history only (right part is future prediction)
		Xnow = (xHistoryInMin / XscaleMinPerPxl).toNumber();
		
		//! draw now position on axis
		dc.setPenWidth(2);
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		dc.drawLine(X1 + Xnow, Y1 - mCtrY * 2 / 50, X1 + Xnow, Y2);

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
			dc.drawLine(X1 - 10, Y2 - i * Yframe, X2 + 10, Y2 - i * Yframe);
		}

		dc.setPenWidth(1);
		var lastPoint = [0, 0, 0];
		var Ymax = 100; //max value for battery

		//! draw history data
		for (var i = 0; i < chartData.size(); i++) {
			//DEBUG*/ logMessage(i + " " + chartData[i]);
			// End (closer to now)
			var timeEnd = chartData[i][TIMESTAMP];
			var dataTimeDistanceInMinEnd = ((timeMostRecentPoint - timeEnd) / 60).toNumber();

			var battery = chartData[i][BATTERY].toFloat() / 1000.0;
			var colorBat = getBatteryColor(battery);

			if (dataTimeDistanceInMinEnd > xHistoryInMin) {
				continue; // This data point is outside of the graph view, ignore it
			}
			else {
				var ySolar = null;
				if (chartData[i].size() == 3) {
					var solar, dataHeightSolar;
					solar = chartData[i][SOLAR];
					if (solar != null) {
						dataHeightSolar = (solar * Yframe) / Ymax;
						ySolar = Y2 - dataHeightSolar;
					}
				}

				var dataHeightBat = (battery * Yframe) / Ymax;
				var yBat = Y2 - dataHeightBat;
				var dataTimeDistanceInPxl = dataTimeDistanceInMinEnd / XscaleMinPerPxl;
				var x = X1 + Xnow - dataTimeDistanceInPxl;
				if (i > 0) {
					dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
					dc.fillRectangle(x, yBat, lastPoint[0] - x + 1, Y2 - yBat);
					if (ySolar && lastPoint[2] != null) {
						dc.setColor(Gfx.COLOR_DK_RED, Gfx.COLOR_TRANSPARENT);
						dc.drawLine(x, ySolar, lastPoint[0], lastPoint[2]);
					}

				}
				lastPoint = [x, yBat, ySolar];
			}
			
			// Start (further to now)
			var timeStart = chartData[i][TIMESTAMP];
			var dataTimeDistanceInMinStart = ((timeMostRecentPoint - timeStart)/60).toNumber();

			if (dataTimeDistanceInMinStart > xHistoryInMin){
				continue; // This data point is outside of the graph view, ignore it
			}
			else {
				var dataTimeDistanceInPxl = dataTimeDistanceInMinStart / XscaleMinPerPxl;
				var x = X1 + Xnow - dataTimeDistanceInPxl;
				dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
				dc.fillRectangle(x, lastPoint[1], lastPoint[0] - x + 1, Y2 - lastPoint[1]);
				lastPoint = [x, lastPoint[1], lastPoint[2]];
			}
		}

		//! draw future estimation
		if (whichView == SCREEN_PROJECTION) {
			dc.setPenWidth(1);
			if (downSlopeSec != null){
				
				var pixelsAvail = Xframe - Xnow;
				var timeDistanceMin = pixelsAvail * XscaleMinPerPxl;
				var xStart = X1 + Xnow;
				var xEnd = xStart + pixelsAvail;
				var valueStart = chartData[0][BATTERY].toFloat() / 1000.0;
				var valueEnd = valueStart + -downSlopeSec * 60.0 * timeDistanceMin;
				if (valueEnd < 0){
					timeDistanceMin = valueStart / (downSlopeSec * 60.0);
					valueEnd = 0;
					xEnd = xStart + timeDistanceMin / XscaleMinPerPxl;
				}
				var yStart = Y2 - (valueStart * Yframe) / Ymax;
				var yEnd = Y2 - (valueEnd * Yframe) / Ymax;
			
				dc.setColor(COLOR_PROJECTION, Gfx.COLOR_TRANSPARENT);
				var triangle = [[xStart, yStart], [xEnd, yEnd], [xStart, yEnd], [xStart, yStart]];
				dc.fillPolygon(triangle);
			}
		}

		//! x-legend
		dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		var timeStr = minToStr(xHistoryInMin, false);
		dc.drawText(27, Y2 + 1, (mFontType > 0 ? mFontType - 1 : 0),  "<-" + timeStr, Gfx.TEXT_JUSTIFY_LEFT);
		
		timeStr = minToStr(xFutureInMin, false);
		dc.drawText(mCtrX * 2 - 27, Y2 + 1, (mFontType > 0 ? mFontType - 1 : 0), timeStr + "->", Gfx.TEXT_JUSTIFY_RIGHT);
		
		if (downSlopeSec != null){
			var timeLeftMin = (100.0 / (downSlopeSec * 60.0)).toNumber();
			timeStr = minToStr(timeLeftMin, false);
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, mCtrY * 2 - mFontHeight - mFontHeight / 2, (mFontType > 0 ? mFontType - 1 : 0), "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
		}
    }

    function LastChargeData(data) {
		for (var i = 0; i < data.size() - 1; i++){
			if (data[i][BATTERY] > data[i + 1][BATTERY]){
				return data[i];
			}
		}
    	return null;
    }
    
    function timeLastFullCharge(data, minTime) {
		for (var i = 0; i < data.size(); i++){
			if (data[i][BATTERY] == 100000) { // 100% is 100000 here as we * by 1000 to get three digit precision
				if (minTime == null || data[0][TIMESTAMP] - minTime < data[i][TIMESTAMP] ) { // If we ask for a minimum time to display, honor it, even if we saw a full charge already
					return data[i][TIMESTAMP];
				}
			}
		}
    	return data[data.size() - 1][TIMESTAMP];
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

	public function getPanelIndex() {
		return(mPanelIndex);
	}

	public function getPanelSize() {
		return(mPanelSize);
	}
}

(:background)
function downSlope(data) { //data is history data as array / return a slope in percentage point per second
	var size = data.size();
	//DEBUG*/ Sys.print("["); for (var i = 0; i < size; i++) { Sys.print(data[i]); if (i < size - 1) { Sys.print(","); } } Sys.println("]");

	//DEBUG*/ logMessage(data);
	if (size <= 2){
		return null;
	}

	// Don't run too often, it's CPU intensive!
	var lastRun = objectStoreGet("LAST_SLOPE_CALC", 0);
	var now = Time.now().value();
	if (now < lastRun + 5) {
		var lastSlope = objectStoreGet("LAST_SLOPE_VALUE", null);
		if (lastSlope != null) {
			//DEBUG*/ logMessage("Retreiving last stored slope (" + lastSlope + ")");
			return lastSlope;
		}
	}
	objectStorePut("LAST_SLOPE_CALC", now);

	var slopes = new [0];

	var count = 0;
	var sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
	var arrayX = new [0];
	var arrayY = new [0];
	var keepGoing = true;
	var batDiff = data[0][BATTERY] - data[1][BATTERY];

	for (var i = 0, j = 0; i < size; i++) {
		if (batDiff < 0) { // Battery going down or staying level (or we are the last point in the dataset), build data for Correlation Coefficient and Standard Deviation calculation
			var diffX = data[j][TIMESTAMP] - data[i][TIMESTAMP];
			var battery = data[i][BATTERY].toFloat() / 1000.0;
			//DEBUG*/ logMessage("i=" + i + " batDiff=" + batDiff + " diffX=" + secToStr(diffX) + " battery=" + battery + " count=" + count);
			sumXY += diffX * battery;
			sumX += diffX;
			sumY += battery;
			sumX2 += (diffX.toLong() * diffX.toLong()).toLong();
			//DEBUG*/ logMessage("diffX=" + diffX + " diffX * diffX=" + diffX * diffX + " sumX2=" + sumX2);
			sumY2 += battery * battery;
			arrayX.add(diffX);
			arrayY.add(battery);
			count++;

			if (i == size - 1) {
				//DEBUG*/ logMessage("Stopping this serie because 'i == size - 1'");
				keepGoing = false; // We reached the end of the array, calc the last slope if we have more than one data
			}
			else if (i < size - 2) {
				batDiff = data[i + 1][BATTERY] - data[i + 2][BATTERY]; // Get direction of the next battery level for next pass
			}
			else {
				//DEBUG*/ logMessage("Doing last data entry in the array");
				// Next pass is for the last data in the array, process it 'as is' since we were going down until then (leave batDiff like it was)
			}
		}
		else {
			keepGoing = false;
			//DEBUG*/ logMessage("i=" + i + " batDiff=" + batDiff);
		}

		if (keepGoing) {
			continue;
		}

		if (count > 1) { // We reached the end (i == size - 1) or we're starting to go up in battery level, if we have at least two data (count > 1), calculate the slope
			var standardDeviationX = Math.stdev(arrayX, sumX / count);
			var standardDeviationY = Math.stdev(arrayY, sumY / count);
			var r = (count * sumXY - sumX * sumY) / Math.sqrt((count * sumX2 - sumX * sumX) * (count * sumY2 - sumY * sumY));
			var slope = r * (standardDeviationY / standardDeviationX);
			//DEBUG*/ logMessage("count=" + count + " sumX=" + sumX + " sumY=" + sumY.format("%0.3f") + " sumXY=" + sumXY.format("%0.3f") + " sumX2=" + sumX2 + " sumY2=" + sumY2.format("%0.3f") + " stdevX=" + standardDeviationX.format("%0.3f") + " stdevY=" + standardDeviationY.format("%0.3f") + " r=" + r.format("%0.3f") + " slope=" + slope);

			slopes.add(slope);

			// var diffY = data[i][BATTERY].toFloat() / 1000.0 - data[j][BATTERY].toFloat() / 1000.0;
			// var diffX = data[j][TIMESTAMP] - data[i][TIMESTAMP];
			// /*DEBUG*/ logMessage("count=" + count + " diffX=" + diffX + " sec (" + secToStr(diffX) + ") diffY=" + diffY.format("%0.3f") + "%");
			// if (diffX != 0) {
			// 	var slope = diffY / diffX;
			// 	/*DEBUG*/ logMessage("slope=" + slope);
			// 	slopes.add(slope);
			// }
		}

		// Reset of variables for next pass if we had something in them from last pass
		if (count > 0) {
			count = 0;
			sumXY = 0; sumX = 0; sumY = 0; sumX2 = 0; sumY2 = 0;
			arrayX = new [0];
			arrayY = new [0];
		}

		// Prepare for the next set of data
		j = i + 1;
		keepGoing = true;

		if (j < size - 2) {
			batDiff = data[j][BATTERY] - data[j + 1][BATTERY]; // Get direction of thr next battery level for next pass
			//DEBUG*/ logMessage("i=" + j + " batDiff=" + batDiff);
		}
	}

	if (slopes.size() == 0){
		//DEBUG*/ logMessage("No slope to calculate");
		return null;
	}
	else {
		//DEBUG*/ logMessage("Slopes=" + slopes);
		var sumSlopes = 0;

		// // Calc the total time these slopes have happened so we car prorate them
		// var time = 0;
		// for (var i = 0; i < slopes.size(); i++) {
		// 	time += slopes[i][1];
		// }
		for (var i = 0; i < slopes.size(); i++) {
			sumSlopes += slopes[i];
		}
		//DEBUG*/ logMessage("sumSlopes=" + sumSlopes);
		var avgSlope = sumSlopes / slopes.size();
		//DEBUG*/ logMessage("avgSlope=" + avgSlope);

		objectStorePut("LAST_SLOPE_VALUE", avgSlope); // Store it so we can retreive it quickly if we're asking too frequently

		return avgSlope;
	}
}
