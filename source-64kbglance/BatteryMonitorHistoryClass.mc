using Toybox.Application as App;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Application.Properties;

(:glance)
class HistoryClassGlance  {
    private var mIsSolar;
    private var mElementSize;
	private var mHistory;
	private var mHistorySize;
	private var mHistoryModified; // The current history array has been modified and will need to be saved when we exit
	private var mHistoryNeedsReload; // A reload is when the full history needs to be rebuilt from scratch since the history arrays have changed
	private var mFullHistoryNeedsRefesh; // A refresh is when only the current history array needs to be readded to the full history
	private var mMaxArrays;
	private var mHandlingFullArray;
	private var mShrinkingInProgress;

    function initialize() {
		//DEBUG*/ logMessage("HistoryClass.initialize");
		mIsSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		mElementSize = mIsSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
        mHistorySize = 0;
		mShrinkingInProgress = false;

		onSettingsChanged(true);
    }

    function onSettingsChanged(fromInit) {
		mMaxArrays = 5;
		try {
			mMaxArrays = Properties.getValue("MaxArrays");
		} catch (e) {
			mMaxArrays = 5;
		}

		mHandlingFullArray = 0;
		try {
			mHandlingFullArray = Properties.getValue("HowHandleFullArray");
		} catch (e) {
			mHandlingFullArray = 0;
		}
	}

	function getLatestHistoryFromStorage() {
		mHistory = null; // Free up memory if we had any set aside
		mHistorySize = 0;

		while (true) {
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
			if (historyArray != null && historyArray.size() > 0) {
				if (mShrinkingInProgress == true || self.shrinkArraysIfNeeded(historyArray)) { // If we're already spawn a shrink (averaging) process, wait until it terminates before testing again!)
					Ui.requestUpdate();
					return; // We're coming back at the top as we have shrunk our size;
				}

				mHistory = $.objectStoreGet("HISTORY_" + historyArray[historyArray.size() - 1], null);
				if (mHistory != null && mHistory.size() == HISTORY_MAX * mElementSize) {
					//DEBUG*/ recalcHistorySize(); logMessage("getLatest.. Read " + mHistorySize + " from " + "HISTORY_" + historyArray[historyArray.size() - 1]);
					//DEBUG*/ Sys.println(historyArray); var start = mHistory[0 + TIMESTAMP]; Sys.println(start); Sys.print("["); for (var i = 0; i < mHistorySize; i++) { Sys.print(mHistory[i*3 + TIMESTAMP] - start + "," + mHistory[i*3 + BATTERY] + "," + mHistory[i*3 + SOLAR]); if (i < mHistorySize - 1) { Sys.print(","); } } Sys.println("];");
					break;
				 }
				 else {
					 // We had corruption? Drop it and try again
				 	//DEBUG*/ if (mHistory == null) { logMessage("Unable to read from HISTORY_" + historyArray[historyArray.size() - 1] + ". Dropping it"); } else { logMessage("HISTORY_" + historyArray[historyArray.size() - 1] + "is too short at " + mHistory.size()); }
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
				//DEBUG*/ logMessage("Old HISTORY_KEY format found, dropping it");
				$.objectStoreErase("HISTORY_KEY", null);
			}
		
			history = $.objectStoreGet("HISTORY", null);
			if (history != null) {
				//DEBUG*/ logMessage("Converting old history format to new one");
				var i = 0;
				while (i < history.size()) {
					mHistory = null;
					mHistory = new [HISTORY_MAX * mElementSize];
					for (var j = 0; i < history.size() && j < HISTORY_MAX * mElementSize; i++, j++) {
						mHistory[j] = history[i];
					}

					historyArray.add(mHistory[0 + TIMESTAMP]);
					$.objectStorePut("HISTORY_" + mHistory[0 + TIMESTAMP], mHistory);
					//DEBUG*/ logMessage("HISTORY_" + mHistory[0 + TIMESTAMP] + " added to store with " + (mHistory.size() / mElementSize) + " elements");
				}

				$.objectStorePut("HISTORY_ARRAY", historyArray);
				$.objectStoreErase("HISTORY"); // And erase the old data
			}
		}

		if (mHistory == null) {
			//DEBUG*/ logMessage("Starting from fresh!");
			mHistory = new [HISTORY_MAX * mElementSize];
		}

		recalcHistorySize();
		mHistoryModified = false;
		mHistoryNeedsReload = true;
		mFullHistoryNeedsRefesh = true;
	}

	function storeHistory(modified) {
		if (mHistory == null) {
			//DEBUG */ logMessage("storeHistory: mHistory is NULL");
			return;
		}

        var timestamp = mHistory[0 + TIMESTAMP];
		if (timestamp == null) {
			//DEBUG */ logMessage("storeHistory: empty mHistory, not saving");
			return;
		}

		if (modified == true) {
			//DEBUG */ logMessage("(storeHistory) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
			//DEBUG */ logMessage("storeHistory: Saving HISTORY_" + timestamp);
			$.objectStoreErase("HISTORY_" + timestamp); // Remove it first as it seems to drop the memory used by objectStorePut
			$.objectStorePut("HISTORY_" + timestamp, mHistory); // Store our history using the first timestamp for a key
		}

		var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
		var index = historyArray.indexOf(timestamp);
		if (index == -1) { // If that key isn't in the array of histories, add it
			historyArray.add(timestamp);
			$.objectStorePut("HISTORY_ARRAY", historyArray);
			//DEBUG */ logMessage("storeHistory: historyArray now " + historyArray);
			self.shrinkArraysIfNeeded(historyArray);
		}
		//DEBUG*/ else if (index != historyArray.size() - 1) { logMessage("storeHistory: HISTORY_" + timestamp + " found at position #" + index + " instead of " + (historyArray.size() - 1) + " of " + historyArray); }

		mHistoryModified = false;
	}

	function shrinkArraysIfNeeded(historyArray) {
		if (historyArray.size() > mMaxArrays) { // But if we already have the max history arrays
			if (mHandlingFullArray == 0) { // drop the earliest one
				//DEBUG*/ logMessage("Too many history arrays, droping HISTORY_" + historyArray[0]);
				$.objectStoreErase("HISTORY_" + historyArray[0]);
				$.objectStoreErase("SLOPES_" + historyArray[0]);
				historyArray.remove(historyArray[0]);
				$.objectStorePut("HISTORY_ARRAY", historyArray);
				mHistoryNeedsReload = true;

				return true;
			}
			else { // Average earliest one with the one before (but do that in its own timer thread and yes, we'll have an extra array until this merge is completed)
				//DEBUG*/ logMessage("Too many history arrays, spawning averageHistoryTimer in 100 msec");
				mShrinkingInProgress = true;
				var timer = new Timer.Timer();
				timer.start(method(:averageHistoryTimer), 50, false);
				return true;
			}
		}

		return false;
	}

	function averageHistoryTimer() {
		mShrinkingInProgress = false; // If we're here, we can safely say we're not shrinking as we won't be interupted until we're done

		var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
		if (historyArray.size() > 1) { // Can't average if we have less than two arrays...
			//DEBUG*/ logMessage("Too many history arrays, averaging HISTORY_" + historyArray[0] + " and HISTORY_" + historyArray[1] + " into HISTORY_" + historyArray[0]);
	        //DEBUG */ logMessage("Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");

			var destHistory = $.objectStoreGet("HISTORY_" + historyArray[0], null); // First the first pass, source and destination is the same as we're shrinking by two
			//DEBUG */ logMessage("(destHistory) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
			if (destHistory != null && destHistory.size() == HISTORY_MAX * mElementSize) { // Make sure both arrays are fine
				for (var i = 0; i < HISTORY_MAX; i += 2) {
					var destIndex = i / 2 * mElementSize;
					var srcIndex = i * mElementSize;
					var bat1 = destHistory[srcIndex + BATTERY];
					var bat2 = destHistory[srcIndex + mElementSize + BATTERY]; // (same as (i + 1) * mElementSize) but without the penalty of a multiplication)
					var batMarkers = (bat1 & 0xF000) | (bat2 & 0xF000);
					destHistory[destIndex + TIMESTAMP] = destHistory[srcIndex + TIMESTAMP]; // We keep the timestamp of the earliest data
					destHistory[destIndex + BATTERY] = (($.stripMarkers(bat1) + $.stripMarkers(bat2)) / 2) | batMarkers; // And average the batteru
					if (mIsSolar) {
						destHistory[destIndex + SOLAR] = (destHistory[srcIndex + SOLAR] + destHistory[srcIndex + mElementSize + SOLAR]) / 2; // and the solar, if available
					}
				}
			}
			else { // Something is wrong, delete it and remove it from our history array
				//DEBUG*/ logMessage("HISTORY_" + historyArray[0] + " is only " + destHistory.size() + " instead of " + (HISTORY_MAX * mElementSize) + ". Dropping it");
				$.objectStoreErase("HISTORY_" + historyArray[0]);
				$.objectStoreErase("SLOPES_" + historyArray[0]);
				historyArray.remove(historyArray[0]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				$.objectStorePut("HISTORY_ARRAY", historyArray);
				return; // We simply return since we cleared up space to accomodate a new history array
			}

			var srcHistory = $.objectStoreGet("HISTORY_" + historyArray[1], null);
			//DEBUG */ logMessage("(srcHistory) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
			if (srcHistory != null && srcHistory.size() == HISTORY_MAX * mElementSize) { // Make sure both arrays are fine
				for (var i = 0; i < HISTORY_MAX; i += 2) {
					var destIndex = ((HISTORY_MAX + i) / 2) * mElementSize;
					var srcIndex = i * mElementSize;
					var bat1 = srcHistory[srcIndex + BATTERY];
					var bat2 = srcHistory[srcIndex + mElementSize + BATTERY];
					var batMarkers = (bat1 & 0xF000) | (bat2 & 0xF000);
					destHistory[destIndex + TIMESTAMP] = srcHistory[srcIndex + TIMESTAMP]; // We keep the timestamp of the earliest data
					destHistory[destIndex + BATTERY] = (($.stripMarkers(bat1) + $.stripMarkers(bat2)) / 2) | batMarkers;
					if (mIsSolar) {
						destHistory[destIndex + SOLAR] = (srcHistory[srcIndex + SOLAR] + srcHistory[srcIndex + mElementSize + SOLAR]) / 2;
					}
				}

				//DEBUG */ logMessage("(before clear src) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
				srcHistory = null; // Clear up the memory used by the source as we don't use it anymore
				//DEBUG */ logMessage("(before put) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
				$.objectStoreErase("HISTORY_" + historyArray[0]); // Remove it first as it seems to drop the memory used by objectStorePut
				$.objectStorePut("HISTORY_" + historyArray[0], destHistory);
				//DEBUG */ logMessage("(after put) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");

				destHistory = null; // Clear up the memory used by the destination as we don't use it anymore
				//DEBUG */ logMessage("(after clear dest) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");

				// Now add the slopes
				var slopes0 = $.objectStoreGet("SLOPES_" + historyArray[0], []);
				var slopes1 = $.objectStoreGet("SLOPES_" + historyArray[1], []);
				//DEBUG */ logMessage("(slopes) Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");
				if (slopes0.size() != 0 && slopes1.size() != 0) {
					slopes0[0].addAll(slopes1[0]);
					for (var i = 0; i < slopes0[0].size() - 1 && slopes0[0].size() > 10 ; i++) { // Average the earliest slopes until we have have a max of 10 slopes (size is going down by one because of the .remove within)
						slopes0[0][i] = (slopes0[0][i] + slopes0[0][i + 1]) / 2; // Average the two adjacent slopes
						slopes0[0].remove(slopes0[0][i + 1]); // And delete the second one now that it's averaged into the first one
					}
					$.objectStorePut("SLOPES_" + historyArray[0], slopes0);
				}

				// Now clean up
				$.objectStoreErase("HISTORY_" + historyArray[1]);
				$.objectStoreErase("SLOPES_" + historyArray[1]);
				historyArray.remove(historyArray[1]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				//DEBUG*/ logMessage("HISTORY_ARRAY now has " + historyArray);
				$.objectStorePut("HISTORY_ARRAY", historyArray);

			}
			else { // Something is wrong, delete it and remove it from our history array
				//DEBUG*/ logMessage("HISTORY_" + historyArray[1] + " is only " + srcHistory.size() + " instead of " + (HISTORY_MAX * mElementSize) + ". Dropping it");
				$.objectStoreErase("HISTORY_" + historyArray[1]);
				$.objectStoreErase("SLOPES_" + historyArray[1]);
				historyArray.remove(historyArray[1]);
				mHistoryNeedsReload = true;
				mFullHistoryNeedsRefesh = true;

				$.objectStorePut("HISTORY_ARRAY", historyArray);

				return; // We simply return since we cleared up space to accomodate a new history array
			}
		}
		else {
			//DEBUG*/ logMessage("Can't average, only " + historyArray.size() + " history arrays. Need at least 2!");
		}
	}

    function getData() {
        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
        var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
        var now = Time.now().value(); //in seconds from UNIX epoch in UTC
        var nowData = [now, battery, solar];

        if (Sys.getSystemStats().charging) {
            var chargingData = objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                objectStorePut("STARTED_CHARGING_DATA", nowData);
            }
            //DEBUG*/ logMessage("getData: Charging " + nowData);
            $.objectStorePut("LAST_CHARGE_DATA", nowData);
    }
        else {
            objectStoreErase("STARTED_CHARGING_DATA");
        }

        var activityStartTime = Activity.getActivityInfo().startTime;
        if (activityStartTime != null) { // we'll hack the battery level to flag that an activity is running by 'ORing' 0x1000 (4096) to the battery level
            nowData[BATTERY] |= 0x1000;
        }

        return nowData;
    }

    function analyzeAndStoreData(data, dataSize, storeAlways) {
        //DEBUG*/ logMessage("analyzeAndStoreData");

        if (data == null) {
            return 0;
        }
        
        var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
        var added = 0;

        if (lastHistory == null) { // no data yet (if we haven't got a last history, we can safely assume history was also empty)
            for (var dataIndex = 0; dataIndex < dataSize && mHistorySize < HISTORY_MAX; dataIndex++, mHistorySize++) { // Now add the new ones (if any)
                mHistory[mHistorySize * mElementSize + TIMESTAMP] = data[dataIndex][TIMESTAMP];
                mHistory[mHistorySize * mElementSize + BATTERY] = data[dataIndex][BATTERY];
                if (mIsSolar) {
                    mHistory[mHistorySize * mElementSize + SOLAR] = data[dataIndex][SOLAR];
                }
            }

            lastHistory = data[dataSize - 1];
            added = dataSize;
            //DEBUG*/ logMessage("analyze: First addition (" + added + ") " + data);
        }
        else { // We have a history and a last history, see if the battery value is different than the last and if so, store it but ignore this is we ask to always store
            var dataIndex;
            for (dataIndex = 0; dataIndex < dataSize && storeAlways == false; dataIndex++) {
                if ($.stripMarkers(lastHistory[BATTERY]) != $.stripMarkers(data[dataIndex][BATTERY])) { // Look for the first new battery level since last time
                    break; // Found it!
                }
                else {
                    //DEBUG*/ logMessage("Ignored " + data[dataIndex]);
                }
            }

            var chargeData;
            
            //DEBUG*/ var addedData = []; logMessage("analyze: mHistorySize " + mHistorySize + " dataSize " + dataSize);
            for (; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
                if (mHistorySize >= HISTORY_MAX) { // We've reached 500 (HISTORY_MAX), start a new array
                    self.storeHistory(added > 0 || mHistoryModified == true); // Store the current history if modified and create a new one based on the latest time stamp

                    // Now start fresh
                    mHistory = null; // Reclaims history space
                    mHistory = new [HISTORY_MAX * mElementSize];
                    mHistorySize = 0;
                    mHistoryNeedsReload = true; // Flag so we can rebuild our full history based on the new history arrays
                }

                if (lastHistory != null && lastHistory[BATTERY] < data[dataIndex][BATTERY]) { // If our last battery value is less than the current one, we were charging
                    if (chargeData == null || chargeData[BATTERY] < data[dataIndex][BATTERY]) { // Keep the highest battery level
                        chargeData = data[dataIndex];
                    }
                }

                // No history or we asked to always store (for markers) or the battery value is diffenrent than the previous one, store
                if (mHistorySize == 0 || storeAlways || mHistory[((mHistorySize - 1) * mElementSize) + BATTERY] != data[dataIndex][BATTERY]) {
                    mHistory[mHistorySize * mElementSize + TIMESTAMP] = data[dataIndex][TIMESTAMP];
                    mHistory[mHistorySize * mElementSize + BATTERY] = data[dataIndex][BATTERY];
                    if (mIsSolar) {
                        mHistory[mHistorySize * mElementSize + SOLAR] = data[dataIndex][SOLAR];
                    }

                    mHistorySize++;
                    added++;

                    //DEBUG*/ addedData.add(data[dataIndex]);
                }
                else {
                    //DEBUG*/ logMessage("Ignored " + data[dataIndex]);
                }
            }

            // If we found new charge data (should be the case only if we charged through USB as the standard method of charging is detected through Sys.getSystemStats().charging)
            if (chargeData != null) {
                //DEBUG*/ logMessage("analyzeAndStoreData: Charging " + chargeData);
                $.objectStorePut("LAST_CHARGE_DATA", chargeData);
            }

            //DEBUG*/ logMessage("Added (" + added + ") " + addedData);
            if (added > 0) {
                if (mIsSolar) {
                    lastHistory = [mHistory[(mHistorySize - 1) * mElementSize + TIMESTAMP], mHistory[(mHistorySize - 1) * mElementSize + BATTERY], mHistory[(mHistorySize - 1) * mElementSize + SOLAR]]; // TIMESTAMP, BATTERY, SOLAR
                }
                else {
                    lastHistory = [mHistory[(mHistorySize - 1) * mElementSize + TIMESTAMP], mHistory[(mHistorySize - 1) * mElementSize + BATTERY]]; // TIMESTAMP, BATTERY
                }
            }
        }

        if (added > 0) {
            //DEBUG*/ logMessage("Added " + added + ". history now " + mHistorySize);
            objectStorePut("LAST_HISTORY_KEY", lastHistory);
            mHistoryModified = true;
            mFullHistoryNeedsRefesh = true;
        }

        return added;
    }

    function downSlope(fromInit) { //data is history data as array / return a slope in percentage point per second
        //DEBUG*/ var startTime = Sys.getTimer();
        //DEBUG*/ logMessage("Calculating slope");
        var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
        var historyArraySize = historyArray.size();

        var totalSlopes = [];
        var firstPass = true; // In case we have no history arrays yet, we still need to process our current in memory history
        var slopeNeedsCalc = false; // When we're done, we don't need to come back to calculate more slopes (beside the active history)
        for (var index = 0; index < historyArraySize || firstPass == true; index++) {
            firstPass = false;
            var slopes = null;
            var slopesStartPos = 0;
            if (historyArraySize > 0) {
                var slopesData = $.objectStoreGet("SLOPES_" + historyArray[index], null);
                if (slopesData != null) {
                    slopes = slopesData[0];
                    slopesStartPos = slopesData[1];
                } 
            }
            if (slopes == null || (slopesStartPos != HISTORY_MAX && (fromInit == false || historyArraySize <= 1 ))) { // Slopes not calculated yet for that array or the array isn't fully calculated (if from init, only use the prebuilt array if they are available otherwise calc for only one slope)
                var data;
                var size;
                if (index == historyArraySize - 1 || historyArraySize == 0) { // Last history is from memory
                    data = mHistory;
                    size = mHistorySize;
                    //DEBUG*/ logMessage("History: size " + size + " start@" + slopesStartPos);
                }
                else {
                    data = $.objectStoreGet("HISTORY_" + historyArray[index], null);
                    //DEBUG*/ logMessage("Calculating slope for HISTORY_" + historyArray[index]);
                    if (data == null) {
                        //DEBUG*/ logMessage("Skipping because it can't be found");
                        continue; // Skip this one if we can't read it. Can happen when arrays have been merged but not accounting for yet
                    }
                    size = self.findPositionInArray(data, 0);
                    slopesStartPos = 0;
                }

                if (size <= 2) {
                    continue;
                }

                slopes = [];

                var count = 0;
                var sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
                var arrayX = [];
                var arrayY = [];
                var keepGoing = true;

                if (slopesStartPos >= size) { // Sanity check that we don't go over the size of our filled array
                    slopesStartPos = 0;
                    $.objectStoreErase("SLOPES_" + historyArray[index]);
                }

                var i = slopesStartPos, j = slopesStartPos;

                var bat1 = $.stripMarkers(data[slopesStartPos * mElementSize + BATTERY]);
                var bat2 = $.stripMarkers(data[(slopesStartPos + (slopesStartPos < size - 1 ? 1 : 0)) * mElementSize + BATTERY]); // Make sure we don't go over the max size of the array with that +1
                var batDiff = bat2 - bat1;

                for (; i < size; i++) {
                    if (batDiff < 0) { // Battery going down or staying level (or we are the last point in the dataset), build data for Correlation Coefficient and Standard Deviation calculation
                        var diffX = data[i * mElementSize + TIMESTAMP] - data[j * mElementSize + TIMESTAMP];
                        var battery = $.stripMarkers(data[i * mElementSize + BATTERY]) / 10.0;

                        //DEBUG*/ logMessage("i=" + i + " batDiff=" + batDiff + " diffX=" + secToStr(diffX) + " battery=" + battery + " count=" + count);
                        sumXY += diffX * battery;
                        sumX += diffX;
                        sumY += battery;
                        sumX2 += (diffX.toLong() * diffX.toLong()).toLong();
                        sumY2 += battery * battery;
                        //DEBUG*/ logMessage("diffX=" + diffX + " diffX * diffX=" + diffX * diffX + " sumX2=" + sumX2 + " sumY2=" + sumY2);
                        arrayX.add(diffX);
                        arrayY.add(battery);
                        count++;

                        if (i == size - 1) {
                            //DEBUG*/ logMessage("Stopping this serie because we've reached the end so calculate the last slope of this array");
                            keepGoing = false; // We reached the end of the array, calc the last slope if we have more than one data
                        }
                        else if (i < size - 2) {
                            bat1 = $.stripMarkers(data[(i + 1) * mElementSize + BATTERY]);
                            bat2 = $.stripMarkers(data[(i + 2) * mElementSize + BATTERY]);
                            batDiff = bat2 - bat1; // Get direction of the next battery level for next pass
                        }
                        else {
                            //DEBUG*/ logMessage("Doing last data entry in the array");
                            // Next pass is for the last data in the array, process it 'as is' since we were going down until then (leave batDiff like it was)
                        }
                    }
                    else {
                        keepGoing = false;
                        //DEBUG*/ logMessage("Stopping at i=" + i + " batDiff=" + batDiff);
                    }

                    if (keepGoing) {
                        continue;
                    }

                    if (count > 1) { // We reached the end (i == size - 1) or we're starting to go up in battery level, if we have at least two data (count > 1), calculate the slope
                        var standardDeviationX = Math.stdev(arrayX, sumX / count);
                        var standardDeviationY = Math.stdev(arrayY, sumY / count);
                        var r = (count * sumXY - sumX * sumY) / Math.sqrt((count * sumX2 - sumX * sumX) * (count * sumY2 - sumY * sumY));
                        var slope = -(r * (standardDeviationY / standardDeviationX));
                        //DEBUG*/ logMessage("count=" + count + " sumX=" + sumX + " sumY=" + sumY.format("%0.3f") + " sumXY=" + sumXY.format("%0.3f") + " sumX2=" + sumX2 + " sumY2=" + sumY2.format("%0.3f") + " stdevX=" + standardDeviationX.format("%0.3f") + " stdevY=" + standardDeviationY.format("%0.3f") + " r=" + r.format("%0.3f") + " slope=" + slope);

                        slopes.add(slope);
                        totalSlopes.add(slope);

                        if (fromInit) { // If running from the Initialisation function, stop after going through one downslope. We'll let the timer handle the others
                            j = i + 1;
                            slopeNeedsCalc = true; // Flag that we'll need to go in next time to finish up
                            break;
                        }
                    }

                    // Reset of variables for next pass if we had something in them from last pass
                    if (count > 0) {
                        count = 0;
                        sumXY = 0; sumX = 0; sumY = 0; sumX2 = 0; sumY2 = 0;
                        arrayX = new [0];
                        arrayY = new [0];
                    }

                    // Prepare for the next set of data
                    if (i == size - 1) {
                        break; // We've reached the end of our array, don't touch 'j' so we can store it later on to point where we need to start again next time around
                    }

                    j = i + 1;
                    keepGoing = true;

                    if (j < size - 1) {
                        bat1 = $.stripMarkers(data[j * mElementSize + BATTERY]);
                        bat2 = $.stripMarkers(data[(j + 1) * mElementSize + BATTERY]);
                        batDiff = bat2 - bat1; // Get direction of the next battery level for next pass
                        //DEBUG*/ logMessage("i=" + j + " batDiff=" + batDiff);
                    }
                }

                if (slopes.size() > 0) {
                    //DEBUG*/ logMessage("Slopes=" + slopes /*+ " start " + (size != HISTORY_MAX ? j : HISTORY_MAX) + (historyArraySize > 0 ? " for HISTORY_" + historyArray[index] : " with no historyArray")*/);
                    var slopesName;
                    var posInHistory;
                    if (size != HISTORY_MAX || historyArraySize == 0) { // We're working on the live history file and not a stored one
                        slopesName = data[0 + TIMESTAMP];
                        posInHistory = j; // j is the starting position of the last known serie of down movement in the array
                    }
                    else {
                        slopesName = historyArray[index];
                        posInHistory = HISTORY_MAX;
                    }
                    $.objectStorePut("SLOPES_" + slopesName, [slopes, posInHistory]);
                }

                if (index < historyArraySize - 1) {
                    slopeNeedsCalc = true; // Flag that we need to come back for more HISTORY_... to be calculated
                }
                break;
            }
            else {
                totalSlopes.addAll(slopes);
            }
        }

        // If we have no slopes, return null
        var slopesSize = totalSlopes.size();
        if (slopesSize == 0) {
            return [null, true];
        }

        var sumSlopes = 0;
        for (var i = 0; i < slopesSize; i++) {
            sumSlopes += totalSlopes[i];
        }
        var avgSlope = sumSlopes / slopesSize;
        //DEBUG*/ logMessage("avgSlope=" + avgSlope + " for " + slopesSize + " slopes");
        //DEBUG*/ var endTime = Sys.getTimer(); logMessage("downslope took " + (endTime - startTime) + "msec");

        return [avgSlope, slopeNeedsCalc];
    }

    function initDownSlope() {
        var downSlopeSec;
        var historyLastPos;

        var downSlopeData = $.objectStoreGet("LAST_SLOPE_DATA", null);
        if (downSlopeData != null) {
            downSlopeSec = downSlopeData[0];
            historyLastPos = downSlopeData[1];
        }
        if (downSlopeSec == null || historyLastPos != mHistorySize) { // onBackgroundData added data since we last ran our slope calc last time we ran the app
            var downSlopeResult = self.downSlope(true);
            downSlopeData = [downSlopeResult[0], mHistorySize];
            $.objectStorePut("LAST_SLOPE_DATA", downSlopeData);
        }
    }

    function findPositionInArray(array, index) {
        // Are we empty?
        if (array[0 + TIMESTAMP] == null) {
            index = 0;
            //DEBUG*/ logMessage("index " + index + " because is empty");
        }

        // Are we full already?
        else if (array[(HISTORY_MAX - 1) * mElementSize + TIMESTAMP] != null) {
            index = HISTORY_MAX;
            //DEBUG*/ logMessage("index " + index + " found at 500");
        }

        // Are we already at the right location?
        else if (index > 0 && array[(index - 1) * mElementSize + TIMESTAMP] != null && array[(index) * mElementSize + TIMESTAMP] == null) {
            index = index;
            //DEBUG*/ logMessage("index " + index + " is already at the right place");
        }

        // Have just moved by one?
        else if (index < HISTORY_MAX - 1 && array[index * mElementSize + TIMESTAMP] != null && array[(index + 1) * mElementSize + TIMESTAMP] == null) {
            index++;
            //DEBUG*/ logMessage("index " + index + " found at next");
        }

        // Use a variation of a binary search to find the size. Worst case will be 8 iterations
        else {
            //DEBUG*/ var oldHistorySize = index;
            var nextTest = ((HISTORY_MAX - index) * 10 / 2 + 5) / 10; // This is the same as x / 2.0 + 0.5 but without the floating performance point penalty
            var count = 0; 
            index += nextTest;
            while (nextTest > 0 && count < 16) { // Sanity check so we don't get stuck in an infinity loop. We should find out spot in 8 tries max so if we're taking double, assume the current index is now correct
                count++;
                nextTest = (nextTest * 10 / 2 + 5) / 10; // We're going to look in half the data so prepare that variable
                if (array[index * mElementSize + TIMESTAMP] == null) { // If we're null, look down
                    if (index > 0 && array[(index - 1) * mElementSize + TIMESTAMP] != null) { // The one below us isn't null, we found our first none empty before null, index is our size
                        break;
                    }
                    index -= nextTest;
                }
                else { // We have data, look up
                    if (index < HISTORY_MAX - 1 && array[(index + 1) * mElementSize + TIMESTAMP] == null) {  // The one above us is null, we found our first none empty before null, index + 1 is our size
                        index++;
                        break; 
                    }
                    index += nextTest;
                }
            }

            //DEBUG*/ logMessage("index " + index + " found in " + count + " tries, started at " + oldHistorySize);
        }

        return index;
    }

	function saveLastData() {
        var lastData = self.getData();
        //DEBUG*/ logMessage("Saving last viewed data " + lastData);
        self.analyzeAndStoreData([lastData], 1, false);
        $.objectStorePut("LAST_VIEWED_DATA", lastData);
    }

	function setHistory(history) {
		mHistory = history;
		mHistorySize = 0;
		recalcHistorySize();
		mHistoryNeedsReload = true;
		mFullHistoryNeedsRefesh = true;

		return [mHistory, mHistorySize];
	}

	function getHistorySize() {
        return mHistorySize;
    }

	function recalcHistorySize() {
		if (mHistory == null) {
			mHistorySize = 0;
			return mHistorySize;
		}

		//DEBUG*/ logMessage("(1) mHistorySize is " + mHistorySize + " mHistory.size() is " + mHistory.size() + " mElementSize is " + mElementSize);

		var historySize = mHistory.size();
		if (historySize != HISTORY_MAX * mElementSize) {
			//DEBUG*/ logMessage("mHistory is " + mHistory.size() + "elements instead of " + HISTORY_MAX * mElementSize + "! Resizing it");
			var newHistory = new [HISTORY_MAX * mElementSize];
			var i;
			for (i = 0; i < historySize && i < HISTORY_MAX * mElementSize; i++) {
				newHistory[i] = mHistory[i];
			}

			mHistory = newHistory;
			mHistorySize = i / mElementSize;

			return mHistorySize;
		}

		// Sanity check. If our previous position (mHistorySize - 1) is null, start from scratch, otherwise start from our current position to improve performance
		if (mHistorySize == null || mHistorySize > HISTORY_MAX || (mHistorySize > 0 && mHistory[(mHistorySize - 1) * mElementSize + TIMESTAMP] == null)) {
			//DEBUG*/ if (mHistorySize != 0) { logMessage("mHistorySize was " + mHistorySize); }
			mHistorySize = 0;
		}

		mHistorySize = self.findPositionInArray(mHistory, mHistorySize);

		return mHistorySize;
	}

	function getHistory() {
		return mHistory;
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

    function isSolar() {
        return mIsSolar;
    }

    function getElementSize() {
        return mElementSize;
    }

	(:debug)
	function buildFakeHistory() {
		// var start = 1753641833;
		// var history = [0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,-300,883,0,0,881,0,300,880,0,600,879,0,900,4971,0,1200,4966,0,1500,4962,0,1800,4959,0,2100,4954,0,2400,4950,0,2700,4946,0,3000,4941,0,3300,4936,0,3600,4932,0,3900,829,0,4200,824,0,4801,823,0,5101,822,0,5401,821,4,6601,820,0,7201,819,0,8103,814,0,8403,803,24,8702,792,0,9002,791,0,9302,790,0,9602,789,0,10202,788,88,10803,787,0,11102,786,0,11402,785,0,12002,784,0,12302,783,0,12903,782,0,13203,781,0,14104,780,0,14403,779,0,15004,778,0,15604,777,0,16803,776,0,17103,775,0,18003,774,0,18304,773,0,18904,772,0,18968,771,0,19028,769,0,19204,768,0,19335,767,0,19503,766,0,19803,760,0,20103,748,0,20357,738,0,20403,737,0,20703,733,0,21003,732,0,21603,731,0,21787,730,0,21800,8922,0,21904,4823,0,22204,4819,0,22503,4815,0,22803,4811,0,23104,4808,0,23404,4804,0,23494,704,0,23500,8896,0,23572,702,0,23704,700,0,24004,693,0,24304,688,0,24904,687,0,25504,686,0,25804,685,0,26704,684,0,26999,682,0,27081,681,0,27305,680,0,27905,679,0,28505,678,0,28806,677,0,28990,676,0,29023,8868,0,29105,675,0,29706,674,0,30305,673,0,30605,672,0,30905,671,0,31205,670,0,31805,669,0,32105,668,0,32705,667,0,33005,666,0,33305,665,0,33606,664,0,33906,663,0,34207,662,0,34807,661,0,35107,660,0,35706,659,0,36007,658,0,36606,657,0,36906,656,0,37206,655,0,37807,654,0,38106,653,0,38706,652,0,39307,651,0,39606,650,0,40206,649,0,40806,648,0,41106,647,0,41706,646,0,42307,645,0,42606,644,0,43207,643,0,43506,642,0,44106,641,0,44706,640,0,45006,639,0,45606,638,0,46206,637,0,46506,636,0,47106,635,0,47707,634,0,48007,633,0,48606,632,0,49506,631,0,50106,630,0,50706,629,0,51307,628,0,51907,627,0,52806,626,0,53407,625,0,54006,624,0,54606,623,0,55506,622,0,56406,621,0,57006,620,0,57606,619,0,58507,618,0,59106,617,0,60007,616,0,60906,615,0,60965,8807,0,61023,614,0,61088,613,0,61148,611,0,61206,609,0,61268,607,0,61328,606,0,61388,605,0,61407,604,0,61506,4698,0,61806,601,0,62106,600,0,63307,599,0,63907,598,0,66006,594,0,66306,588,0,66521,587,0,66583,586,0,66585,585,0,66907,579,0,66936,578,0,66997,577,0,67117,576,0,67177,575,0,67297,574,0,67357,573,0,67477,572,0,67537,571,0,67657,570,0,67717,569,0,67806,568,0,67897,567,0,68017,566,0,68107,565,0,68586,564,0,68600,8756,0,68664,563,0,68724,562,0,68784,561,0,68904,560,0,68964,559,0,68975,8751,0,69307,558,0,69607,4645,14,69907,4639,8,70208,4633,5,70517,4628,14,70816,4622,19,71117,4615,15,71416,4611,43,71716,4606,16,72016,500,0,72316,494,0,72617,493,0,73517,492,0,74116,490,0,74716,489,0,75316,488,0,75616,487,0,76517,486,0,76816,485,0,77716,484,0,78617,482,0,78916,481,0,79216,480,0,79517,479,0,79816,478,0,120916,215,0,120977,213,0,121227,211,0,121826,210,0,122126,209,0,122726,208,0,123026,207,0,123328,205,0,123927,204,0,124228,203,0,124529,202,0,125129,201,0,125429,200,0,126029,199,0,126329,198,0,126929,197,0,127229,196,0,127529,195,0,127829,194,0,128129,193,0,128730,192,0,129030,191,0,129330,190,0,129930,189,0,130231,188,0,130530,187,0,131131,186,0,131431,185,0,132031,184,0,132331,183,0,132932,182,0,133232,181,0,133832,180,0,134132,179,0,134732,178,0,135033,177,0,135633,176,0,135933,175,0,136532,174,0,136833,173,0,137433,172,0,138032,171,0,138332,170,0,138632,169,0,139232,168,0,139532,167,0,140133,166,0,140432,165,0,140732,164,0,141032,163,0,141632,162,0,141932,161,0,142532,160,0,143132,159,0,143432,158,0,143733,157,0,144333,156,0,144632,155,0,145233,154,0,145832,153,0,146132,152,0,146432,150,0,146494,149,0,146554,147,0,146614,145,0,146674,143,0,146732,141,0,146794,140,0,146854,139,0,146914,137,0,146974,135,0,147032,133,0,147094,131,0,147154,130,0,147214,128,0,147274,126,0,147332,124,0,147394,122,0,147454,120,0,147514,119,0,147574,117,0,147632,115,0,147694,113,0,147754,111,0,147814,109,0,147874,107,0,147932,105,0,147994,104,0,148054,102,0,148114,100,0,148174,98,0,148232,97,0,148264,96,0,148287,95,0,148311,94,0,148532,104,0,148832,149,0,149132,194,0,149432,239,0,149732,285,0,150032,330,0,150333,376,0,150633,421,0,150933,467,0,151233,512,0,151533,4637,3,151724,4632,29,151810,4630,30,151833,4629,7,151876,4628,10,152133,4624,18,152433,4620,21,152753,4614,14,152868,514,0,152929,512,0,153053,510,0,153369,509,0,153669,507,0,153969,511,0,154269,556,0,154569,602,0,154869,647,0,155169,692,0,155469,735,0,155769,775,3,155970,774,0,156030,773,0,156056,772,0,156088,771,0,156369,765,0,156669,761,0,157570,760,0,157870,759,0,158770,758,0,159671,757,0,159970,756,0,160570,755,0,160870,754,0,161170,753,0,162070,752,0,162670,751,0,163870,750,0,164170,749,0,164770,748,0,165071,747,0,165370,746,78,166570,745,0,166703,744,0,166763,743,0,167470,742,0,168371,741,0,169270,740,0,169372,739,0,169871,738,0,170170,737,0,170770,736,60,171670,735,17,172571,734,8,173471,733,8,174372,732,0,174972,731,0,175572,730,0,175872,729,0,176173,728,0,176772,727,0,177372,726,0,178574,725,0,179174,724,0,179774,723,0,180674,722,0,181274,721,0,182174,720,0,183074,719,0,183674,718,0,184274,717,0,185474,716,0,185867,715,0,185948,714,0,186976,728,0,187275,726,4,187875,724,1,187985,723,0,190667,717,0,190727,715,0,201992,607,0,202592,606,0,203193,605,0,203792,604,0,204392,603,0,204993,602,0,205892,601,0,206492,600,0,206793,599,0,207393,598,0,207692,597,0,208592,596,0,211597,896,0,211682,894,0,211742,892,0];
		// mHistory = new [HISTORY_MAX * 3];
		// for (var i = 0; i < history.size(); i += 3) {
		// 	mHistory[i] = history[i] + start;
		// 	mHistory[i+1] = history[i+1];
		// 	mHistory[i+2] = history[i+2];
		// }
		// mHistorySize = history.size() / 3;

		// logMessage("Building fake history");
	    // var now = Time.now().value(); //in seconds from UNIX epoch in UTC
		// var span = 60 * 2460; // 1 day 16 hours
		// var start = now - span;
		// var size = span / (5 * 60); // One entry per 5 minutes
		// var batInitialLevel = 80.0;
		// var batLastLevel = 5.0;
		// var batDrain = (batInitialLevel - batLastLevel) / size;
		// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;
		// mHistory = new [HISTORY_MAX * elementSize];
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
	function eraseAllData() {
		// $.objectStorePut("HISTORY", mHistory); // And erase the old data
		// var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
		// if (historyArray != null) {
		// 	for (var i = 0; i < historyArray.size(); i++) {
		// 		$.objectStoreErase("HISTORY_" + historyArray[i]);
		// 	}
		// 	$.objectStoreErase("HISTORY_ARRAY");
		// }
	}

	(:release)
	function eraseAllData() {
	}

	(:can_viewloop)
	function canViewLoop() {} // If it's there, we can call the viewloop functions. Without this, I get compile errors
}
