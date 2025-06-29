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
        	if (!(history instanceof Toybox.Lang.Array)) {
	       		var battery = Sys.getSystemStats().battery;
        		dc.drawText(mCtrX, mCtrY, Gfx.FONT_MEDIUM, "No data has yet\nbeen recorded\n\nBattery = " + battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);
        	}
			else { //there is an array
        		drawChart(dc, [10, mCtrX * 2 - 10, mCtrY - mCtrY / 2, mCtrY + mCtrY / 2], history);
        	}
        }
    }
    
	function drawChart(dc, xy, chartDataNormalOrder) {
    	var X1 = xy[0], X2 = xy[1], Y1 = xy[2], Y2 = xy[3];
    	var chartData = chartDataNormalOrder.reverse();
		var scale = mCtrY * 2.0 / 240.0; // 240 was the default resolution of the watch used at the time this widget was created

		//! Display current charge level with the appropriate color
		var colorBat;
		var battery = Sys.getSystemStats().battery;

		if (battery >= 20) {
			colorBat = COLOR_BAT_OK;
		}
		else if (battery >= 10) {
			colorBat = COLOR_BAT_LOW;
		}
		else {
			colorBat = COLOR_BAT_CRITICAL;
		}

		dc.setColor(colorBat, Gfx.COLOR_TRANSPARENT);
		dc.drawText(mCtrX, 20 * mCtrY * 2 / 240, Gfx.FONT_LARGE, battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);

    	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
    	dc.setPenWidth(2);

		//! Calculate projected usage slope
    	var downSlopeSec = null;
    	if (chartData instanceof Array && chartData[0] != null) {
    		downSlopeSec = downSlope(chartData);
	    	var downSlopeStr = "";
	    	var timeLeftSecUNIX = null;
			
			var yPos = 35 * scale;
		    if (downSlopeSec != null) {
				dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
				if (gViewScreen == SCREEN_DATA_HR) {
					var downSlopeMin = downSlopeSec * 60;
					downSlopeStr = minToStr(battery / downSlopeMin);
					dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Remaining", Gfx.TEXT_JUSTIFY_CENTER);
					yPos += mFontHeight;
					dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
				}
				else if (gViewScreen == SCREEN_DATA_DAY) {
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

				battery = (chartData[0][BATTERY].toFloat() / 1000.0).toNumber();
				var timeLeftSec = (battery / downSlopeSec).toNumber();
				timeLeftSecUNIX = timeLeftSec + chartData[0][TIMESTAMP_END];
		    }
			else {
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.drawText(mCtrX, yPos, Gfx.FONT_XTINY, "More data needed...", Gfx.TEXT_JUSTIFY_CENTER);		    	
		    }
			yPos += mFontHeight;

			//! Data views
			if (gViewScreen == SCREEN_DATA_HR || gViewScreen == SCREEN_DATA_DAY) {
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
					dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/h" : "%/day");
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

				var lastChargeData = LastChargeData(chartData);
				if (lastChargeData != null) {
					batUsage = (chartData[0][BATTERY] - lastChargeData[BATTERY]).toFloat() / 1000.0;
					timeDiff = chartData[0][TIMESTAMP_END] - lastChargeData[TIMESTAMP_START];
					if (timeDiff != 0.0) {
						var dischargeRate = batUsage * 60 * 60 * (gViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
						dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/h" : "%/day");
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
					lastChargeHappened = minToStr((Time.now().value() - lastChargeData[TIMESTAMP_END]) / 60) + " ago";
				}
				else {
					lastChargeHappened = "N/A";
				}
				yPos += mFontHeight;
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, lastChargeHappened, Gfx.TEXT_JUSTIFY_CENTER);
			}

			//! Graphical views
			if (gViewScreen == SCREEN_HISTORY || gViewScreen == SCREEN_PROJECTION) {
				var Yframe = Y2 - Y1;// pixels available for level
				var Xframe = X2 - X1;// pixels available for time
				var timeMostRecentPoint = chartData[0][TIMESTAMP_END];
				var timeMostFuturePoint = (timeLeftSecUNIX != null && gViewScreen == SCREEN_PROJECTION) ? timeLeftSecUNIX : timeMostRecentPoint;
				var timeLeastRecentPoint = timeLastFullCharge(chartData);
				var xHistoryInMin = (timeMostRecentPoint - timeLeastRecentPoint).toFloat() / 60.0; // max value for time in minutes
				xHistoryInMin = MIN(MAX(xHistoryInMin, 60.0), 60.0 * 25.0 * 30.0);
				var xFutureInMin = (timeMostFuturePoint - timeMostRecentPoint).toFloat() / 60.0; // max value for time in minutes
				xFutureInMin = MIN(MAX(xFutureInMin, 60.0), (gViewScreen == SCREEN_PROJECTION ? 60.0 * 25.0 * 30.0 : 0));
				var XmaxInMin = xHistoryInMin + xFutureInMin;// max value for time in minutes
				var XscaleMinPerPxl = XmaxInMin / Xframe;// in minutes per pixel
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

					battery = chartData[i][BATTERY].toFloat() / 1000.0;
					if (battery >= 20) {
						colorBat = COLOR_BAT_OK;
					}
					else if (battery >= 10) {
						colorBat = COLOR_BAT_LOW;
					}
					else {
						colorBat = COLOR_BAT_CRITICAL;
					}

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
				if (gViewScreen == SCREEN_PROJECTION) {
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
				var timeStr = minToStr(xHistoryInMin);
				dc.drawText(27, Y2 + 1, Gfx.FONT_TINY,  "<-" + timeStr, Gfx.TEXT_JUSTIFY_LEFT);
				
				timeStr = minToStr(xFutureInMin);
				dc.drawText(mCtrX * 2 - 27, Y2 + 1, Gfx.FONT_TINY, timeStr + "->", Gfx.TEXT_JUSTIFY_RIGHT);
				
				if (downSlopeSec != null){
					var timeLeftMin = (100.0 / (downSlopeSec * 60.0)).toNumber();
					timeStr = minToStr(timeLeftMin);
					dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
					dc.drawText(mCtrX, mCtrY * 2 - mFontHeight - mFontHeight / 2, Gfx.FONT_SMALL, "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
				}
			}
    	}
			
		//! Now add the 'popup' if the device is currently charging
		if (System.getSystemStats().charging) {
			dc.setPenWidth(2);
			dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
			dc.fillRoundedRectangle(27, mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * 27, 2 * (mFontHeight + mFontHeight / 2), 5);
			dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
			dc.drawRoundedRectangle(27, mCtrY - (mFontHeight + mFontHeight / 2), mCtrX * 2 - 2 * 27, 2 * (mFontHeight + mFontHeight / 2), 5);
			battery = Sys.getSystemStats().battery;
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
		
		//DEBUG
	    //dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
    	//dc.drawText(mCtrX, Y2 +1, Gfx.FONT_TINY, charDataSize, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function LastChargeData(data) {
		for (var i = 0; i < data.size() - 1; i++){
			if (data[i][BATTERY] > data[i + 1][BATTERY]){
				return data[i];
			}
		}
    	return null;
    }
    
    function timeLastFullCharge(data) {
		for (var i = 0; i < data.size(); i++){
			if (data[i][BATTERY] == 100000) { // 100% is 100000 here as we * by 1000 to get three digit precision
				return data[i][TIMESTAMP_END];
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
//	data = [[2, 9, 90000], [10, 20, 100000], [21, 31, 90000], [40, 50, 80000], [55, 60, 85000], [61, 71, 90000], [73, 83, 80000], [85, 100, 75000], [101, 150, 80000]].reverse();
//	data = [[1751167593, 1751167604, 82430],[1751167561, 1751167563, 82315],[1751167536, 1751167536, 81904],[1751167236, 1751167236, 77626],[1751166936, 1751166939, 73255],[1751166636, 1751166636, 68834],[1751166336, 1751166336, 64400],[1751166036, 1751166036, 59967],[1751165736, 1751165736, 55533],[1751165550, 1751165550, 52872],[1751165436, 1751165436, 51100],[1751165136, 1751165136, 46662],[1751164929, 1751164929, 43553],[1751164836, 1751164836, 42229],[1751164536, 1751164536, 37807],[1751164236, 1751164236, 33415],[1751164149, 1751164149, 32091],[1751163979, 1751163979, 29442],[1751163936, 1751163936, 29006],[1751163883, 1751163883, 28118],[1751163707, 1751163707, 26280],[1751163636, 1751163636, 26382],[1751163408, 1751163408, 26448],[1751159506, 1751159506, 27361],[1751159372, 1751159381, 27604],[1751159206, 1751159206, 27682],[1751149002, 1751149002, 30096],[1751148962, 1751148970, 30162],[1751148919, 1751148919, 30265],[1751148702, 1751148702, 30302],[1751148469, 1751148469, 30639],[1751148265, 1751148265, 31034],[1751147965, 1751147965, 31577],[1751147665, 1751147665, 32103],[1751147365, 1751147365, 32605],[1751147221, 1751147221, 32642],[1751147180, 1751147180, 32745],[1751146880, 1751146880, 33234],[1751146602, 1751146602, 33271],[1751145486, 1751145486, 33621],[1751145469, 1751145469, 33645],[1751145402, 1751145402, 33658],[1751142485, 1751142488, 34094],[1751142401, 1751142401, 34106],[1751142162, 1751142170, 34505],[1751142101, 1751142101, 34649],[1751140590, 1751140607, 35751],[1751140585, 1751140585, 35792],[1751140300, 1751140300, 35842],[1751140000, 1751140046, 36150],[1751139365, 1751139383, 36319],[1751139100, 1751139100, 36343],[1751138287, 1751138292, 36483],[1751138199, 1751138199, 36500],[1751138131, 1751138131, 36561],[1751138038, 1751138038, 36792],[1751137982, 1751137982, 35920],[1751137682, 1751137682, 31511],[1751137382, 1751137382, 27090],[1751137372, 1751137373, 26654],[1751137142, 1751137142, 23569],[1751137090, 1751137090, 22681],[1751136946, 1751136946, 20485],[1751136884, 1751136884, 19596],[1751136790, 1751136790, 18992],[1751136765, 1751136774, 19095],[1751136679, 1751136679, 19366],[1751136373, 1751136379, 20049],[1751136099, 1751136099, 20098],[1751133222, 1751133222, 20830],[1751133113, 1751133113, 21192],[1751132813, 1751132813, 22076],[1751132513, 1751132513, 22874]];
	var size = data.size();
	//DEBUG*/ Sys.print("["); for (var i = 0; i < size; i++) { Sys.print(data[i]); if (i < size - 1) { Sys.print(","); } } Sys.println("]");

	//DEBUG*/ logMessage(data);
	if (size <= 2){
		return null;
	}
	
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
		}

		// Reset of variables for next pass if we had something in them from last pass
		if (count > 0) {
			sumXY = 0; sumX = 0; sumY = 0; sumX2 = 0; sumY2 = 0;
			count = 0;
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
		for (var i = 0; i < slopes.size(); i++){
			sumSlopes += slopes[i];
		}
		//DEBUG*/ logMessage("sumSlopes=" + sumSlopes);
		var avgSlope = sumSlopes / slopes.size();
		//DEBUG*/ logMessage("avgSlope=" + avgSlope);
		return avgSlope;
	}
}


		// // goal is to store X1 X2 Y1 Y2 for each downslope (actually up-slope because reversed array) and store all slopes in array to later do array average.
		// /*DEBUG*/ logMessage("data[" + i + "]=" + data[i] + " diff time is " + (data[i][TIMESTAMP_END] - data[i][TIMESTAMP_START]));
	
		// if (data[i][BATTERY] <= data[i + 1][BATTERY] && i < size - 2 && ((data[0][TIMESTAMP_END] - data[i][TIMESTAMP_END]) / 60 / 60 / 24 < 10)) { // Normal case, battery going down or staying level, less than 10 days ago
		// 	// do nothing, keep progressing in data
		// 	/*DEBUG*/ logMessage("progressing... " + i + " time diff is : " + (data[0][TIMESTAMP_END] - data[i][TIMESTAMP_END]));
		// }
		// else { //battery charged or ran out of data
		// 	/*DEBUG*/ logMessage("action... " + i);
		// 	timeLeastRecent = data[i][TIMESTAMP_START];
		// 	valueLeastRecent = data[i][BATTERY].toFloat() / 1000.0;
		// 	timeMostRecent = data[j + 1][TIMESTAMP_END];
		// 	valueMostRecent = data[j + 1][BATTERY].toFloat() / 1000.0;
		// 	/*DEBUG*/ logMessage(timeLeastRecent + " " + timeMostRecent + " " + valueLeastRecent + " " + valueMostRecent);
		// 	if (timeMostRecent - timeLeastRecent < 1 * 60 * 60) { // if less than 1 hours data
		// 		/*DEBUG*/ logMessage("discard... " + i + " time diff is " + (timeMostRecent - timeLeastRecent) + " sec");
		// 		//discard
		// 	}
		// 	else { //save
		// 		/*DEBUG*/ logMessage("save... " + i);
		// 		var slope = (valueLeastRecent - valueMostRecent).toFloat() / (timeLeastRecent - timeMostRecent).toFloat();
		// 		if (slope < 0){
		// 			slopes.add(slope);
		// 		}
		// 		/*DEBUG*/ logMessage("slopes " + slopes);
		// 	}
		// 	j = i;
		// }
