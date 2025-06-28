using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;

class BatteryMonitorView extends Ui.View {

	var mCtrX, mCtrY;
	var mTimer;
	var mLastData;
	var mNowData;
	var mRefreshCount;

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
			var data = getData();
			/*DEBUG*/ logMessage("Adding data " + data);
			analyzeAndStoreData(data);
			mRefreshCount = 0;

		}
		Ui.requestUpdate();
	}

    // Load your resources here
    function onLayout(dc) {
    	mCtrX = dc.getWidth()/2;
    	mCtrY = dc.getHeight()/2; 
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
		var scale = mCtrY * 2.0 /240.0; // 240 was the default resolution of the watch used at the time this widget was created

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
		dc.drawText(mCtrX, 15 * mCtrY * 2 /240, Gfx.FONT_MEDIUM, battery.toNumber() + "%", Gfx.TEXT_JUSTIFY_CENTER |  Gfx.TEXT_JUSTIFY_VCENTER);

    	dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
    	dc.setPenWidth(2);
    	
		//! Calculate projected usage slope
    	var downSlopeSec = null;
    	if (chartData instanceof Array && chartData[0] != null) {
    		downSlopeSec = downSlope(chartData);
	    	var downSlopeStr = "";
	    	var timeLeftSecUNIX = null;
		    dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
		    if (downSlopeSec != null) {
	    		var downSlopeHours = (downSlopeSec * 60 * 60);
	    		if (downSlopeHours * 24 <= 100){
	    			downSlopeStr = -(downSlopeHours * 24).toNumber() + "%/day";
	    		}
				else {
	    			downSlopeStr = -(downSlopeHours).toNumber() + "%/hour";
	    		}	
	    		downSlopeStr = "Discharge " + downSlopeStr;
	    		
				var timeLeftSec = -((chartData[0][BATTERY].toFloat() / 1000.0) / (downSlopeSec));
				timeLeftSecUNIX = timeLeftSec + chartData[0][TIMESTAMP_END];
				dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
				dc.drawText(mCtrX, 33, Gfx.FONT_TINY, downSlopeStr, Gfx.TEXT_JUSTIFY_CENTER);
		    }
			else {
				dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
				dc.drawText(mCtrX, 33 * scale, Gfx.FONT_XTINY, "More time needed...", Gfx.TEXT_JUSTIFY_CENTER);		    	
		    }

			//! Data views
			if (gViewScreen == SCREEN_DATA_HR || gViewScreen == SCREEN_DATA_DAY) {
				/*DEBUG*/ logMessage(mNowData);
				/*DEBUG*/ logMessage(mLastData);

				//! Bat usage since last view
				var batUsage;
				var timeDiff = 0;
				if (mNowData && mLastData) {
					batUsage = (mNowData[BATTERY] - mLastData[BATTERY]).toFloat() / 1000.0;
					timeDiff = mNowData[TIMESTAMP_END] - mLastData[TIMESTAMP_START];
				}

				/*DEBUG*/ logMessage("Bat usage: " + batUsage);
				/*DEBUG*/ logMessage("Time diff: " + timeDiff);

				var fontHeight = Graphics.getFontHeight(Gfx.FONT_TINY);
				var yPos = 33 * scale + fontHeight;
				
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Since last view", Gfx.TEXT_JUSTIFY_CENTER);
				yPos += fontHeight;

				if (timeDiff > 0 && batUsage < 0) {
					var dischargeRate = batUsage * 60 * 60 * (gViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
					dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/h" : "%/day");
					dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);

					/*DEBUG*/ logMessage("Discharge since last view: " + dischargeRate);
				}
				else {
					dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
					/*DEBUG*/ logMessage("Discharge since last view: N/A");
				}

				//! Bat usage since last charge
				yPos += fontHeight;
				dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "Since Last Chg", Gfx.TEXT_JUSTIFY_CENTER);
				yPos += fontHeight;

				var lastChargeData = LastChargeData(chartData);
				if (lastChargeData != null) {
					batUsage = (chartData[0][BATTERY] - lastChargeData[BATTERY]).toFloat() / 1000.0;
					timeDiff = chartData[0][TIMESTAMP_END] - lastChargeData[TIMESTAMP_START];
					if (timeDiff != 0.0) {
						var dischargeRate = batUsage * 60 * 60 * (gViewScreen == SCREEN_DATA_HR ? 1 : 24) / timeDiff;
						dischargeRate = dischargeRate.abs().format("%0.3f") + (gViewScreen == SCREEN_DATA_HR ? "%/h" : "%/day");
						dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, dischargeRate, Gfx.TEXT_JUSTIFY_CENTER);
						/*DEBUG*/ logMessage("Discharge since last charge: " + dischargeRate);
					}
					else {
						dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
						/*DEBUG*/ logMessage("Discharge since last charge: N/A");
					}
				}
				else {
					dc.drawText(mCtrX, yPos, Gfx.FONT_TINY, "N/A", Gfx.TEXT_JUSTIFY_CENTER);
					/*DEBUG*/ logMessage("Discharge since last charge: N/A");
				}
			}

			//! Graphical views
			if (gViewScreen == SCREEN_HISTORY || gViewScreen == SCREEN_PROJECTION) {
				var Yframe = Y2 - Y1;// pixels available for level
				var Xframe = X2 - X1;// pixels available for time
				var timeMostRecentPoint = chartData[0][TIMESTAMP_END];
				var timeMostFuturePoint = (timeLeftSecUNIX != null && gViewScreen == SCREEN_PROJECTION) ? timeLeftSecUNIX : timeMostRecentPoint;
				var timeLeastRecentPoint = timeLastFullCharge(chartData);
				var xHistoryInMin = (0.0 + timeMostRecentPoint - timeLeastRecentPoint) / 60; // max value for time in minutes
				xHistoryInMin = MIN(MAX(xHistoryInMin, 60), 60 * 25 * 30);
				var xFutureInMin = (0.0 + timeMostFuturePoint - timeMostRecentPoint) / 60; // max value for time in minutes
				xFutureInMin = MIN(MAX(xFutureInMin, 60), (gViewScreen == SCREEN_PROJECTION ? 60 * 25 * 30 : 0));
				var XmaxInMin = xHistoryInMin + xFutureInMin;// max value for time in minutes
				var XscaleMinPerPxl = (0.0 + XmaxInMin) / Xframe;// in minutes per pixel
		    	var Xnow; // position of now in the graph, equivalent to: pixels available for left part of chart, with history only (right part is future prediction)
				Xnow = xHistoryInMin / XscaleMinPerPxl;
				
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
					dc.drawLine(X1 - 10, Y2 - (i * Yframe * scale), X2 + 10, Y2 - (i * Yframe * scale));
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
						var dataHeightBat = (battery * Yframe) / Ymax * scale;
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
						var valueEnd = valueStart + downSlopeSec * 60 * timeDistanceMin;
						if (valueEnd < 0){
							timeDistanceMin = -valueStart / (downSlopeSec * 60);
							valueEnd = 0;
							xEnd = xStart + timeDistanceMin / XscaleMinPerPxl;
						}
						var yStart = Y2 - (valueStart * Yframe) / Ymax * scale;
						var yEnd = Y2 - (valueEnd * Yframe) / Ymax * scale;
					
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
					var timeLeftMin = -(100 / (downSlopeSec * 60));
					timeStr = minToStr(timeLeftMin);
					dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
					dc.drawText(mCtrX, mCtrY * 2 - 43, Gfx.FONT_SMALL, "100% = " + timeStr, Gfx.TEXT_JUSTIFY_CENTER);
				}
			}
    	}
			
		//DEBUG
	    //dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
    	//dc.drawText(mCtrX, Y2 +1, Gfx.FONT_TINY, charDataSize, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function LastChargeData(data){
		for (var i = 0; i < data.size() - 1; i++){
			if (data[i][BATTERY] > data[i + 1][BATTERY]){
				return data[i];
			}
		}
    	return null;
    }
    
    function timeLastFullCharge(data){
		for (var i = 0; i < data.size(); i++){
			if (data[i][BATTERY] == 100000) { // 100% is 100000 here as we * by 1000 to get three digit precision
				return data[i][TIMESTAMP_END];
			}
		}
    	return data[data.size() - 1][TIMESTAMP_START];
    }
    
    function downSlope(data){ //data is history data as array / return a slope in percentage point per second
    	if (data.size() <= 2){
    		return null;
    	}
    	
    	var slopes = new [0];
	    var i = 0, j = 0;
	    
	    var timeMostRecent = data[0][TIMESTAMP_END], timeLeastRecent, valueMostRecent = data[0][BATTERY].toFloat() / 1000.0, valueLeastRecent;
	    for (; i < data.size() - 1; i++) {
		    // goal is to store X1 X2 Y1 Y2 for each downslope (actually up-slope because reversed array) and store all slopes in array to later do array average.
	    	/*DEBUG*/ logMessage("data[" + i + "]=" + data[i] + " diff time is " + (data[i][TIMESTAMP_END] - data[i][TIMESTAMP_START]));
    	
	    	if (data[i][BATTERY] <= data[i + 1][BATTERY] && i < data.size() - 2 && ((data[0][TIMESTAMP_END] - data[i][TIMESTAMP_END]) / 60 / 60 / 24 < 10)) { // Normal case, battery going down or staying level, less than 10 days ago
	    		// do nothing, keep progressing in data
	    		/*DEBUG*/ logMessage("progressing... " + i + " time diff is : " + (data[0][TIMESTAMP_END] - data[i][TIMESTAMP_END]));
	    	}
			else { //battery charged or ran out of data
	    		/*DEBUG*/ logMessage("action... " + i);
	    		timeLeastRecent = data[i][TIMESTAMP_START];
    			valueLeastRecent = data[i][BATTERY].toFloat() / 1000.0;
    			timeMostRecent = data[j + 1][TIMESTAMP_END];
    			valueMostRecent = data[j + 1][BATTERY].toFloat() / 1000.0;
    			/*DEBUG*/ logMessage(timeLeastRecent + " " + timeMostRecent + " " + valueLeastRecent + " " + valueMostRecent);
	    		if (timeMostRecent - timeLeastRecent < 1 * 60 * 60) { // if less than 1 hours data
	    			/*DEBUG*/ logMessage("discard... " + i + " time diff is " + (timeMostRecent - timeLeastRecent) + " sec");
	    			//discard
	    		}
				else { //save
	    			/*DEBUG*/ logMessage("save... " + i);
	    			var slope = (0.0 + valueLeastRecent - valueMostRecent) / (timeLeastRecent - timeMostRecent);
	    			if (slope < 0){
	    				slopes.add(slope);
	    			}
	    			/*DEBUG*/ logMessage("slopes " + slopes);
	    		}
	    		j = i;
	    	}
    	}
    	if (slopes.size() == 0){
    		return null;
    	}
		else {
    		var sumSlopes = 0;
    		for (i = 0; i < slopes.size(); i++){
    			sumSlopes += slopes[i];
    			/*DEBUG*/ logMessage("sumSlopes " + sumSlopes);
    		}
    		var avgSlope = sumSlopes / slopes.size();
    		/*DEBUG*/ logMessage("avgSlope " + avgSlope);
    		return avgSlope;
    	}
    }
    
    function minToStr(min){
    	var str;
    	if (min < 1){
    		str = "Now";
    	}
		else if (min < 60){
    		str = min.toNumber() + "m";
    	}
		else if (min < 60 * 2){
    		var hours = Math.floor(min / 60);
    		var mins = min - hours * 60;
    		str = hours.toNumber() + "h" + mins.format("%02d");
    	}
		else if (min < 60 * 24){
    		var hours = Math.floor(min / 60);
    		var mins = min - hours * 60;
    		str = hours.toNumber() + "h" + mins.format("%02d");
    	}
		else {
    		var days = Math.floor(min / 60 / 24);
    		var hours = Math.floor((min / 60) - days * 24);
    		str = days.toNumber() + "d " + hours.toNumber() + "h";
    	}
    	return str;
    }
    
	function MAX (val1, val2){
		if (val1 > val2){
			return val1;
		}
		else {
			return val2;
		}
	}

	function MIN (val1, val2){
		if (val1 < val2){
			return val1;
		}
		else {
			return val2;
		}
	}
}
