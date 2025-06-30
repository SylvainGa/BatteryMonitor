using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Math;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;

class BatteryMonitorView extends Ui.View {

	var mCtrX, mCtrY;
	var mTimer;
	var mLastData;
	var mNowData;
	var mRefreshCount;
	var mFontHeight;

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
		mRefreshCount = 0;
		mLastData = objectStoreGet("LAST_VIEWED_DATA", null);
		mNowData = getData();
		analyzeAndStoreData(mNowData);
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
		if (mRefreshCount == 60) { // Refresh is 5 seconds, 5 * 60 is 300 seconds, which is the same time the backghround process runs
			mNowData = getData();
			//DEBUG*/ logMessage("Adding data " + mNowData);
			analyzeAndStoreData(mNowData);
			mRefreshCount = 0;
		}
		Ui.requestUpdate();
	}

    // Load your resources here
    function onLayout(dc) {
    	mCtrX = dc.getWidth()/2;
    	mCtrY = dc.getHeight()/2; 

		mFontHeight = Graphics.getFontHeight(Gfx.FONT_TINY);
    }

    // Update the view
    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);		
        dc.clear();

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
        
       	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);	
        
        if (!gAbleBackground){
			dc.drawText(mCtrX, mCtrY, Gfx.FONT_MEDIUM, "Device does not\nsupport background\nprocesses", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
        }
		else {
        	var history = objectStoreGet("HISTORY_KEY", null);
			
			//DEBUG*/ Sys.print("["); for (var i = 0; i < history.size(); i++) { Sys.print(history[i]); if (i < history.size() - 1) { Sys.print(","); } } Sys.println("]");
			/*DEBUG*/ history = [[1751132513, 1751132513, 22874],[1751132813, 1751132813, 22076],[1751133113, 1751133113, 21192],[1751133222, 1751133222, 20830],[1751136099, 1751136099, 20098],[1751136373, 1751136379, 20049],[1751136679, 1751136679, 19366],[1751136765, 1751136774, 19095],[1751136790, 1751136790, 18992],[1751136884, 1751136884, 19596],[1751136946, 1751136946, 20485],[1751137090, 1751137090, 22681],[1751137142, 1751137142, 23569],[1751137372, 1751137373, 26654],[1751137382, 1751137382, 27090],[1751137682, 1751137682, 31511],[1751137982, 1751137982, 35920],[1751138038, 1751138038, 36792],[1751138131, 1751138131, 36561],[1751138199, 1751138199, 36500],[1751138287, 1751138292, 36483],[1751139100, 1751139100, 36343],[1751139365, 1751139383, 36319],[1751140000, 1751140046, 36150],[1751140300, 1751140300, 35842],[1751140585, 1751140585, 35792],[1751140590, 1751140607, 35751],[1751142101, 1751142101, 34649],[1751142162, 1751142170, 34505],[1751142401, 1751142401, 34106],[1751142485, 1751142488, 34094],[1751145402, 1751145402, 33658],[1751145469, 1751145469, 33645],[1751145486, 1751145486, 33621],[1751146602, 1751146602, 33271],[1751146880, 1751146880, 33234],[1751147180, 1751147180, 32745],[1751147221, 1751147221, 32642],[1751147365, 1751147365, 32605],[1751147665, 1751147665, 32103],[1751147965, 1751147965, 31577],[1751148265, 1751148265, 31034],[1751148469, 1751148469, 30639],[1751148702, 1751148702, 30302],[1751148919, 1751148919, 30265],[1751148962, 1751148970, 30162],[1751149002, 1751149002, 30096],[1751159206, 1751159206, 27682],[1751159372, 1751159381, 27604],[1751159506, 1751159506, 27361],[1751163408, 1751163408, 26448],[1751163636, 1751163636, 26382],[1751163707, 1751163707, 26280],[1751163883, 1751163883, 28118],[1751163936, 1751163936, 29006],[1751163979, 1751163979, 29442],[1751164149, 1751164149, 32091],[1751164236, 1751164236, 33415],[1751164536, 1751164536, 37807],[1751164836, 1751164836, 42229],[1751164929, 1751164929, 43553],[1751165136, 1751165136, 46662],[1751165436, 1751165436, 51100],[1751165550, 1751165550, 52872],[1751165736, 1751165736, 55533],[1751166036, 1751166036, 59967],[1751166336, 1751166336, 64400],[1751166636, 1751166636, 68834],[1751166936, 1751166939, 73255],[1751167236, 1751167236, 77626],[1751167536, 1751167536, 81904],[1751167561, 1751167563, 82315],[1751167593, 1751167604, 82430],[1751167620, 1751167637, 82381],[1751167777, 1751167777, 82200],[1751168038, 1751168052, 82134],[1751168808, 1751168808, 81776],[1751169074, 1751169076, 81752],[1751169099, 1751169099, 81686],[1751169234, 1751169234, 81534],[1751170225, 1751170225, 81019],[1751170237, 1751170255, 80978],[1751170259, 1751170259, 80917],[1751170292, 1751170292, 80876],[1751170419, 1751170419, 80736],[1751174540, 1751174540, 79629],[1751174561, 1751174561, 79592],[1751196115, 1751196115, 75673],[1751196252, 1751196252, 75632],[1751196324, 1751196324, 75541],[1751200017, 1751200017, 74887],[1751200120, 1751200126, 74875],[1751200617, 1751200617, 74719],[1751219217, 1751219217, 60662],[1751219516, 1751219516, 60596],[1751219572, 1751219572, 60505],[1751219590, 1751219590, 60440],[1751219673, 1751219673, 60493],[1751225219, 1751225219, 60, 54312],[1751225412, 1751225424, 60300],[1751225434, 1751225447, 60234],[1751225519, 1751225519, 60148],[1751226119, 1751226119, 60608],[1751226967, 1751226967, 65918],[1751227271, 1751227271, 65852],[1751228170, 1751228170, 66880],[1751228474, 1751228474, 67986],[1751229675, 1751229675, 70133],[1751229903, 1751229924, 70055],[1751229977, 1751229977, 69759],[1751232999, 1751232999, 68858],[1751233235, 1751233241, 68846],[1751233293, 1751233293, 68694],[1751233417, 1751233417, 68525],[1751234073, 1751234073, 68344],[1751234132, 1751234139, 68217],[1751234206, 1751234210, 68102],[1751234408, 1751234423, 67962],[1751234499, 1751234499, 67859],[1751237199, 1751237199, 67225],[1751237500, 1751237500, 67036],[1751237799, 1751237799, 66535],[1751237877, 1751237877, 66522],[1751237924, 1751237924, 66444],[1751252501, 1751252501, 51819],[1751252559, 1751252559, 51803],[1751252771, 1751252771, 51276],[1751253689, 1751253689, 51034],[1751254022, 1751254022, 50544]];

        	if (!(history instanceof Toybox.Lang.Array)) {
	       		var battery = Sys.getSystemStats().battery;
        		dc.drawText(mCtrX, mCtrY, Gfx.FONT_MEDIUM, "No data has yet\nbeen recorded\n\nBattery = " + battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
        	}
			else {
				history = history.reverse(); // Data is added at the end and we need it at the top of the array for efficiency when processing so reverse it here

				//! Calculate projected usage slope
				var downSlopeSec = downSlope(history);
				var lastChargeData = LastChargeData(history);
				var nowData = history[0];
				switch (gViewScreen) {
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
				showChargingPopup(dc);
			}
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
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Remaining", Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
			}
			else if (whichView == SCREEN_DATA_DAY) {
				var downSlopeHours = downSlopeSec * 60 * 60;
				if (downSlopeHours * 24 <= 100){
					downSlopeStr = (downSlopeHours * 24).toNumber() + "%/day";
				}
				else {
					downSlopeStr = (downSlopeHours).toNumber() + "%/hour";
				}	
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Discharging", Gfx.TEXT_JUSTIFY_CENTER);
				yPos += mFontHeight;
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
			}
		}
		else {
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, yPos, Gfx.FONT_XTINY, "More data needed...", Gfx.TEXT_JUSTIFY_CENTER);		    	
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
		dc.drawText(mCtrX, mCtrY - (mFontHeight + mFontHeight / 4), Gfx.FONT_SMALL, "Charging " + battery.format("%0.1f") + "%", Gfx.TEXT_JUSTIFY_CENTER);
		var chargingData = objectStoreGet("STARTED_CHARGING_DATA", null);
		if (chargingData) {
			var batUsage = battery - (chargingData[BATTERY]).toFloat() / 1000.0;
			var timeDiff = Time.now().value() - chargingData[TIMESTAMP_START];

			//DEBUG*/ logMessage("Bat usage: " + batUsage);
			//DEBUG*/ logMessage("Time diff: " + timeDiff);
			var chargeRate;
			if (timeDiff > 0) {
				chargeRate = (batUsage * 60 * 60 / timeDiff).format("%0.1f");
			}
			else {
				chargeRate = 0.0f;
			}
			dc.drawText(mCtrX, mCtrY + mFontHeight / 8, Gfx.FONT_SMALL, "Rate " + chargeRate + "%/h", Gfx.TEXT_JUSTIFY_CENTER);
		}
	}

	function showMainPage(dc, downSlopeSec, lastChargeData, nowData) {
		// Draw and color charge gauge
		var xPos = mCtrX * 2 * 3 / 5;
		var width = mCtrX * 2 / 18;
		var height = mCtrY * 2 * 7 / 10 / 5;
		var yPos = mCtrY * 2 * 2 / 10 + 4 * height;

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
			timeDiff = mNowData[TIMESTAMP_END] - mLastData[TIMESTAMP_START];
		}

		//DEBUG*/ logMessage("Bat usage: " + batUsage);
		//DEBUG*/ logMessage("Time diff: " + timeDiff);

		dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Since last view", Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		if (timeDiff > 0 && batUsage < 0) {
			var dischargeRate = batUsage * 60 * 60 * (gViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
			dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/hour" : "%/day");
			dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);

			//DEBUG*/ logMessage("Discharge since last view: " + dischargeRate);
		}
		else {
			dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
			//DEBUG*/ logMessage("Discharge since last view: N/A");
		}

		//! Bat usage since last charge
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Since Last charge", Gfx.TEXT_JUSTIFY_CENTER);
		yPos += mFontHeight;

		if (lastChargeData != null) {
			batUsage = (nowData[BATTERY] - lastChargeData[BATTERY]).toFloat() / 1000.0;
			timeDiff = nowData[TIMESTAMP_END] - lastChargeData[TIMESTAMP_START];
			if (timeDiff != 0) {
				var dischargeRate = batUsage * 60 * 60 * (gViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
				dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/hour" : "%/day");
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
				//DEBUG*/ logMessage("Discharge since last charge: " + dischargeRate);
			}
			else {
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
				//DEBUG*/ logMessage("Discharge since last charge: N/A");
			}
		}
		else {
			dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
			//DEBUG*/ logMessage("Discharge since last charge: N/A");
		}

		//! How long for last charge?
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Last charge happened", Gfx.TEXT_JUSTIFY_CENTER);
		var lastChargeHappened;
		if (lastChargeData) {
			lastChargeHappened = minToStr((Time.now().value() - lastChargeData[TIMESTAMP_END]) / 60, false) + " ago";
		}
		else {
			lastChargeHappened = "N/A";
		}
		yPos += mFontHeight;
		dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, lastChargeHappened, Gfx.TEXT_JUSTIFY_CENTER);

		return yPos;
	}

	function drawChart(dc, xy, whichView, downSlopeSec, chartData) {
		doHeader(dc, whichView, Sys.getSystemStats().battery, downSlopeSec );

    	var X1 = xy[0], X2 = xy[1], Y1 = xy[2], Y2 = xy[3];
		var timeLeftSecUNIX = null;
		if (downSlopeSec != null) {
			var battery = (chartData[0][BATTERY].toFloat() / 1000.0).toNumber();
			var timeLeftSec = (battery / downSlopeSec).toNumber();
			timeLeftSecUNIX = timeLeftSec + chartData[0][TIMESTAMP_END];
		}
		else {
			return;
		}

		//! Graphical views
		var Yframe = Y2 - Y1;// pixels available for level
		var Xframe = X2 - X1;// pixels available for time
		var timeMostRecentPoint = chartData[0][TIMESTAMP_END];
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
		dc.drawLine(X1 + Xnow, Y1 + 1, X1 + Xnow, Y2);

		//! draw y gridlines
		dc.setPenWidth(1);
		var yGridSteps = 0.1;
		for (var i = 0; i <= 1.05; i += yGridSteps){
			if (i == 0 or i == 0.5 or i.toNumber() == 1){
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			}
			else {
				dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
			}
			dc.drawLine(X1 - 10, Y2 - i * Yframe, X2 + 10, Y2 - i * Yframe);
		}

		dc.setPenWidth(1);
		var lastPoint = [0,0];
		var Ymax = 100; //max value for battery

		//! draw history data
		for (var i = 0; i < chartData.size(); i++) {
			//DEBUG*/ logMessage(i + " " + chartData[i]);
			// End (closer to now)
			var timeEnd = chartData[i][TIMESTAMP_END];
			var dataTimeDistanceInMinEnd = ((timeMostRecentPoint - timeEnd) / 60).toNumber();

			var battery = chartData[i][BATTERY].toFloat() / 1000.0;
			var colorBat = getBatteryColor(battery);

			if (dataTimeDistanceInMinEnd > xHistoryInMin) {
				continue; // This data point is outside of the graph view, ignore it
			}
			else {
				var dataHeightBat = (battery * Yframe) / Ymax;
				var yBat = Y2 - dataHeightBat;
				var dataTimeDistanceInPxl = dataTimeDistanceInMinEnd / XscaleMinPerPxl;
				var x = X1 + Xnow - dataTimeDistanceInPxl;
				if (i > 0){ 
					dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
					dc.fillRectangle(x, yBat, lastPoint[0] - x + 1, Y2 - yBat);
				}
				lastPoint = [x, yBat];
			}
			
			// Start (further to now)
			var timeStart = chartData[i][TIMESTAMP_START];
			var dataTimeDistanceInMinStart = ((timeMostRecentPoint - timeStart)/60).toNumber();

			if (dataTimeDistanceInMinStart > xHistoryInMin){
				continue; // This data point is outside of the graph view, ignore it
			}
			else {
				var dataTimeDistanceInPxl = dataTimeDistanceInMinStart / XscaleMinPerPxl;
				var x = X1 + Xnow - dataTimeDistanceInPxl;
				dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
				dc.fillRectangle(x, lastPoint[1], lastPoint[0] - x + 1, Y2 - lastPoint[1]);
				lastPoint = [x, lastPoint[1]];
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
		dc.drawText(27, Y2 + 1, Gfx.FONT_TINY,  "<-" + timeStr, Gfx.TEXT_JUSTIFY_LEFT);
		
		timeStr = minToStr(xFutureInMin, false);
		dc.drawText(mCtrX * 2 - 27, Y2 + 1, Gfx.FONT_TINY, timeStr + "->", Gfx.TEXT_JUSTIFY_RIGHT);
		
		if (downSlopeSec != null){
			var timeLeftMin = (100.0 / (downSlopeSec * 60.0)).toNumber();
			timeStr = minToStr(timeLeftMin, false);
			dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
			dc.drawText(mCtrX, mCtrY * 2 - mFontHeight - mFontHeight / 2, Gfx.FONT_SMALL, "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
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
				if (minTime == null || data[0][TIMESTAMP_START] - minTime < data[i][TIMESTAMP_END] ) { // If we ask for a minimum time to display, honor it, even if we saw a full charge already
					return data[i][TIMESTAMP_END];
				}
			}
		}
    	return data[data.size() - 1][TIMESTAMP_START];
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
			var diffX = data[j][TIMESTAMP_END] - (data[i][TIMESTAMP_START] + (data[i][TIMESTAMP_END] - data[i][TIMESTAMP_START]) / 2);
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
			// var diffX = data[j][TIMESTAMP_START] - data[i][TIMESTAMP_END];
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
