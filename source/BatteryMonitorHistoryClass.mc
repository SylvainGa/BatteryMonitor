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

//! App constants
const HISTORY_MAX = 500; // Quad the max screen size should be enough data to keep but could be too much for large screen so max at 1200 (around 32KB)

//! Object store keys (now they keys are in Storage and are texts, not numbers)
// const HISTORY_KEY = 2;
// const LAST_HISTORY_KEY = 3;
// const LAST_VIEWED_DATA = 4;
// const LAST_CHARGED_DATA = 5;
// const STARTED_CHARGING_DATA = 6;
// const MARKER_DATA = 7;

//! History Array data type
enum {
	TIMESTAMP,
	BATTERY`,
	SOLAR
}

const HISTORY_ELEMENT_SIZE_SOLAR = 3; // Solar watches have three fields of 4 bytes (signed 32 bits) each, TIMESTAMP, BATTERY and SOLAR
const HISTORY_ELEMENT_SIZE = 2; // Non solar watches have two fields of 4 bytes (signed 32 bits) each, TIMESTAMP and BATTERY
(:glance)
class HistoryClass  {
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
	private var mMinimumLevelIncrease; // How much the battery level must INCREASE before a charge event is recorded. Is overridden by the watch flagging a charge event. 
	
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

		mMinimumLevelIncrease = 0;
		try {
			mMinimumLevelIncrease = Properties.getValue("MinimumLevelIncrease");
		} catch (e) {
			mMinimumLevelIncrease = 0;
		}
	}

	function getLatestHistoryFromStorage() {
		mHistory = null; // Free up memory if we had any set aside
		mHistorySize = 0;

		while (true) {
			var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
			if (historyArray != null && historyArray.size() > 0) {
				if (mShrinkingInProgress == true || self.shrinkArraysIfNeeded(historyArray)) { // If we're already spawn a shrink (averaging) process, wait until it terminates before testing again!)
					//DEBUG*/ if (mShrinkingInProgress == true) { logMessage("Waiting for previous spawned shrinking to finish"); } else { logMessage("Spawned shrinking process, waiting for it to finish"); }
					Ui.requestUpdate();
					return; // We're coming back at the top as we have shrunk our size;
				}

				mHistory = $.objectStoreGet("HISTORY_" + historyArray[historyArray.size() - 1], null);
				if (mHistory != null && mHistory.size() == HISTORY_MAX * mElementSize) {
					//DEBUG*/ recalcHistorySize(); logMessage("Read " + mHistorySize + " from " + "HISTORY_" + historyArray[historyArray.size() - 1]);
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
				$.objectStoreErase("HISTORY_KEY");
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
			//DEBUG */ logMessage("storeHistory: Saving HISTORY_" + timestamp);
			//DEBUG */ logMessage("Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
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
				//DEBUG*/ logMessage("Too many history arrays, spawning averageHistoryTimer in 50 msec");
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
	        //DEBUG */ logMessage("Free memory 1 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

			var destHistory = $.objectStoreGet("HISTORY_" + historyArray[0], null); // First the first pass, source and destination is the same as we're shrinking by two
			//DEBUG */ logMessage("Free memory 2 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
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
			//DEBUG */ logMessage("Free memory 3 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
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

				//DEBUG */ logMessage("Free memory 4 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
				srcHistory = null; // Clear up the memory used by the source as we don't use it anymore
				//DEBUG */ logMessage("Free memory 5 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
				$.objectStoreErase("HISTORY_" + historyArray[0]); // Remove it first as it seems to drop the memory used by objectStorePut
				$.objectStorePut("HISTORY_" + historyArray[0], destHistory);
				//DEBUG */ logMessage("Free memory 6 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

				destHistory = null; // Clear up the memory used by the destination as we don't use it anymore
				//DEBUG */ logMessage("Free memory 7 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

				// Now add the slopes
				var slopes0 = $.objectStoreGet("SLOPES_" + historyArray[0], []);
				var slopes1 = $.objectStoreGet("SLOPES_" + historyArray[1], []);
				//DEBUG */ logMessage("Free memory 8 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
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
        var now = Time.now().value(); //in seconds from UNIX epoch in UTC
        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
        var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
        var nowData = [now, battery, solar];

        if (Sys.getSystemStats().charging) {
            var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
	            //DEBUG*/ logMessage("getData: Started charging at " + nowData);
                $.objectStorePut("STARTED_CHARGING_DATA", nowData);
            }
			else {
				if (chargingData[BATTERY] + mMinimumLevelIncrease * 10 < nowData[BATTERY]) { // We're charging, are we going over the threshold to recognize a charging event?
					//DEBUG*/ logMessage("getData: LAST_CHARGE_DATA " + nowData);
					$.objectStorePut("LAST_CHARGE_DATA", nowData);
				}
			}
	    }
        else {
            //DEBUG*/ if ($.objectStoreGet("STARTED_CHARGING_DATA", null) != null) { logMessage("getData: Finished charging at " + nowData); }
            $.objectStoreErase("STARTED_CHARGING_DATA");
        }

        var activityStartTime = Activity.getActivityInfo().startTime;
        if (activityStartTime != null) { // we'll hack the battery level to flag that an activity is running by 'ORing' 0x1000 (4096) to the battery level
            nowData[BATTERY] |= 0x1000;
        }

        return nowData;
    }

    function analyzeAndStoreData(data, dataSize, storeAlways) {
        //DEBUG*/ logMessage("analyzeAndStoreData");

        if (data == null || dataSize == 0) {
            return 0;
        }

		// First see if the data passed has a charge event
		var lastBatteryLevel;
		var lastDataIndex;
		var lastChargeEventIndex;
		var lastDetectedChargeEventIndex;
        var lastUpBatteryLevel = $.objectStoreGet("LAST_UP_BATTERY_LEVEL", null);

		// Start from what we saw last time we ran if possible
		if (lastUpBatteryLevel != null) {
			lastBatteryLevel = lastUpBatteryLevel[BATTERY];
			lastDataIndex = -1;
		}
		else {
			lastBatteryLevel = $.stripMarkers(data[BATTERY]); // (no need for 0 * 3 + BATTERY as just BATTERY is the same)
			lastDataIndex = 0;
		}

		// Go through the data to find the last charge event that happened (for charged through USB as the standard method of charging is detected through Sys.getSystemStats().charging)
		//DEBUG*/  var firstTimestamp = data[TIMESTAMP]; logMessage("Analyse: Looking for charging events starting at " + firstTimestamp + " " + lastBatteryLevel);
		for (var i = 0; i < dataSize; i++) {
			//DEBUG*/ logMessage((data[i * 3 + TIMESTAMP] - firstTimestamp) + " " + $.stripMarkers(data[i * 3 + BATTERY]));
			var curBatteryLevel = $.stripMarkers(data[i * 3 + BATTERY]);
			if (lastBatteryLevel < curBatteryLevel) {
				// Found a charge event by the last battery being less than the current one, flag it if it's the first up trend
				if (lastChargeEventIndex == null) {
					//DEBUG*/ logMessage("First event");
					lastChargeEventIndex = lastDataIndex;
				}

				// Keep going until our treshold is reached (need to account that the first event is from lastUpBatteryLevel)
				if ((lastChargeEventIndex == -1 ? lastUpBatteryLevel[BATTERY] : $.stripMarkers(data[lastChargeEventIndex * 3 + BATTERY])) + mMinimumLevelIncrease * 10 < curBatteryLevel) {
					//DEBUG*/ logMessage("Above threshold of " + mMinimumLevelIncrease);
					lastDetectedChargeEventIndex = i; // lastDetectedChargeEventIndex can NEVER be -1 here so later on, I don't need to check for that
				}
			}
			else {
				 // Charge is going DOWN, if we had a charge event, it's now gone and we need to look for a newer one, if any
				//DEBUG*/ if (lastChargeEventIndex != null) { logMessage("No longer charging"); }
				lastChargeEventIndex = null;
				lastDataIndex = i;
			}

			lastBatteryLevel = curBatteryLevel;
		}

		// If value were still climbing up when we ended, record the start of the climbing so we can go back to it next time
		if (lastChargeEventIndex != null) {
			if (lastChargeEventIndex >= 0) { // We can ignore -1 as this is what is already in LAST_UP_BATTERY_LEVEL
				$.objectStorePut("LAST_UP_BATTERY_LEVEL", [data[lastChargeEventIndex * 3 + TIMESTAMP], $.stripMarkers(data[lastChargeEventIndex * 3 + BATTERY]), data[lastChargeEventIndex * 3 + SOLAR]]);
				//DEBUG*/ logMessage("Ended while climbing");
			}
		}
		else {
			// Otherwise record the last known battery level
			$.objectStorePut("LAST_UP_BATTERY_LEVEL", [data[(dataSize - 1) * 3 + TIMESTAMP], $.stripMarkers(data[(dataSize - 1) * 3 + BATTERY]), data[(dataSize - 1) * 3 + SOLAR]]);
			//DEBUG*/ logMessage("Saving last recorded battery level");
		}

		// Now that we've gone through the list, see if we had a charge event and if we do, see if it's newer than the last recorded charge event
		if (lastDetectedChargeEventIndex != null) {
			//DEBUG*/ logMessage("Charge event recorded at " + [data[lastDetectedChargeEventIndex * 3 + TIMESTAMP], $.stripMarkers(data[lastDetectedChargeEventIndex * 3 + BATTERY]), data[lastDetectedChargeEventIndex * 3 + SOLAR]]);
			var lastChargeData = $.objectStoreGet("LAST_CHARGE_DATA", null);
			if (lastChargeData == null || lastChargeData[TIMESTAMP] < data[lastDetectedChargeEventIndex * 3 + TIMESTAMP]) {
				// Newer one, record it
				//DEBUG*/ logMessage("And it's newer than " + lastChargeData);
				$.objectStorePut("LAST_CHARGE_DATA", [data[lastDetectedChargeEventIndex * 3 + TIMESTAMP], $.stripMarkers(data[lastDetectedChargeEventIndex * 3 + BATTERY]), data[lastDetectedChargeEventIndex * 3 + SOLAR]]);
			}
			//DEBUG*/ else { logMessage("But keeping " + lastChargeData); }
		}

        var added = 0;
        var lastHistory = $.objectStoreGet("LAST_HISTORY_KEY", null);

		// See if we have just started building data and if so, process it quickly
        if (lastHistory == null) { // no data yet (if we haven't got a last history, we can safely assume history was also empty)
            for (var dataIndex = 0; dataIndex < dataSize && mHistorySize < HISTORY_MAX; dataIndex++, mHistorySize++) { // Now add the new ones (if any)
                mHistory[mHistorySize * mElementSize + TIMESTAMP] = data[dataIndex * 3 + TIMESTAMP]; // data is always made of 3 elements, SOLAR is simply always 0 on non solar devices and ignored in history
                mHistory[mHistorySize * mElementSize + BATTERY] = data[dataIndex * 3 + BATTERY];
                if (mIsSolar) {
                    mHistory[mHistorySize * mElementSize + SOLAR] = data[dataIndex * 3 + SOLAR];
                }
            }

			var lastEntry = (dataSize - 1) * 3;
            lastHistory = [data[lastEntry + TIMESTAMP], data[lastEntry + BATTERY], data[lastEntry + SOLAR]];
            added = dataSize;
            //DEBUG*/ logMessage("analyze: First addition (" + added + ") " + data);
        }
        else {
			// We have a history and a last history, see if the battery value is different than the last and if so, store it but ignore this is we ask to always store
            var dataIndex;
            for (dataIndex = 0; dataIndex < dataSize && storeAlways == false; dataIndex++) {
                if (lastHistory[BATTERY] != data[dataIndex * 3 + BATTERY]) { // Look for the first new battery level since last time (don't use stripMarkers here as we want to keep if an activity was started/stop too)
                    break; // Found it!
                }
                else {
                    //DEBUG*/ logMessage("Ignored " + data[dataIndex]);
                }
            }

            //DEBUG*/ var addedData = []; logMessage("analyze: mHistorySize " + mHistorySize + " dataSize " + dataSize);
            for (; dataIndex < dataSize; dataIndex++) { // Now add the new ones (if any)
				var dataPos = dataIndex * 3;
                if (mHistorySize >= HISTORY_MAX) { // We've reached 500 (HISTORY_MAX), start a new array
                    self.storeHistory(added > 0 || mHistoryModified == true); // Store the current history if modified and create a new one based on the latest time stamp

                    // Now start fresh
                    mHistory = null; // Reclaims history space
                    mHistory = new [HISTORY_MAX * mElementSize];
                    mHistorySize = 0;
                    mHistoryNeedsReload = true; // Flag so we can rebuild our full history based on the new history arrays
                }

                // No history or we asked to always store (for markers) or the battery value is diffenrent than the previous one, store
                if (mHistorySize == 0 || storeAlways || mHistory[((mHistorySize - 1) * mElementSize) + BATTERY] != data[dataPos + BATTERY]) {
                    mHistory[mHistorySize * mElementSize + TIMESTAMP] = data[dataPos + TIMESTAMP];
                    mHistory[mHistorySize * mElementSize + BATTERY] = data[dataPos + BATTERY];
                    if (mIsSolar) {
                        mHistory[mHistorySize * mElementSize + SOLAR] = data[dataPos + SOLAR];
                    }

                    mHistorySize++;
                    added++;

                    //DEBUG*/ addedData.addAll([data[dataPos + TIMESTAMP], data[dataPos + BATTERY], data[dataPos + SOLAR]]);
                }
                else {
                    //DEBUG*/ logMessage("Ignored " + [data[dataPos + TIMESTAMP], data[dataPos + BATTERY], data[dataPos + SOLAR]]);
                }
            }

            //DEBUG*/ logMessage("Added (" + added + ") " + addedData);
            if (added > 0) {
				var lastHistoryPos = (mHistorySize - 1) * mElementSize;
                if (mIsSolar) {
                    lastHistory = [mHistory[lastHistoryPos + TIMESTAMP], mHistory[lastHistoryPos + BATTERY], mHistory[lastHistoryPos + SOLAR]]; // TIMESTAMP, BATTERY, SOLAR
                }
                else {
                    lastHistory = [mHistory[lastHistoryPos + TIMESTAMP], mHistory[lastHistoryPos + BATTERY], 0]; // TIMESTAMP, BATTERY, 0 for SOLAR
                }
            }
        }

        if (added > 0) {
            //DEBUG*/ logMessage("Added " + added + ". history now " + mHistorySize);
            //DEBUG*/ logMessage("LAST_HISTORY_KEY " + lastHistory);
            $.objectStorePut("LAST_HISTORY_KEY", lastHistory);
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
        self.analyzeAndStoreData(lastData, 1, false);
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

(:debug)
function RestoreCopiedHistory() {
	// See ..\Garmin\CodeSource\temp\Data.txt
	// $.objectStoreErase("HISTORY_ARRAY");
	// RestoreCopiedHistoryInternal(1769405624, [0,613,0,1802,609,0,4203,605,0,6606,601,0,9007,597,0,11708,593,0,14708,589,0,17409,585,0,19810,581,0,23109,577,0,25210,573,0,27011,569,0,29111,565,0,31511,561,0,33311,557,0,35411,553,0,38112,549,0,39613,545,0,40813,539,0,42614,535,0,44113,530,0,45914,526,0,48617,522,1,49817,4603,0,51017,4585,0,52217,4559,0,53417,4533,1,54617,4506,0,55817,394,0,57317,389,0,58816,385,0,60917,380,0,63017,375,0,64819,371,0,66318,367,0,68119,360,0,69320,353,0,70819,349,0,72020,345,0,73520,341,0,75320,336,0,77120,332,0,78620,328,0,79820,324,0,81619,320,0,83119,316,0,84619,312,0,86420,308,0,87920,304,0,90020,299,0,92120,294,0,93620,290,0,95419,286,0,96920,282,0,98420,278,0,100220,274,0,101719,270,0,103219,266,0,105020,262,0,106520,258,0,108020,254,0,110120,249,0,111921,245,0,113421,241,0,114621,222,0,115820,217,0,117020,211,0,118221,367,0,119721,411,0,122120,407,0,123621,4473,21,124821,4449,18,126021,4428,35,127221,4401,24,128421,4378,7,129621,261,7,130822,257,0,132023,252,0,133524,248,0,135025,243,0,136225,239,0,137726,235,0,139226,231,0,140726,227,0,142226,223,0,144027,218,0,145527,214,0,147328,210,0,148830,206,0,150930,201,0,152430,195,0,154531,191,0,156934,187,0,159034,183,0,160834,179,0,162634,175,0,164434,171,0,166536,166,0,167735,347,0,168935,537,0,170136,727,0,170736,764,0,172238,762,0,173738,760,0,174938,758,0,176439,756,0,178541,754,0,179441,752,0,180941,750,0,183040,748,0,184541,746,0,186042,744,0,187542,742,0,189643,740,0,191144,738,0,193545,736,0,194746,734,0,196245,732,0,197446,730,0,198946,728,0,199846,726,0,200747,724,0,201647,722,0,202847,720,0,204347,718,0,204947,716,0,206148,714,0,207047,712,0,208248,710,0,209448,708,0,210948,706,0,211848,4787,14,212447,4777,19,213048,4768,24,213647,4758,27,214248,4748,38,214848,642,28,215748,631,2,216948,628,0,217848,625,0,218447,623,0,219048,621,0,219647,619,0,220547,617,0,221447,615,0,222349,613,0,223549,611,0,224450,609,0,225650,607,0,226850,605,0,227750,603,0,228950,601,0,230152,599,0,231052,597,0,232553,595,0,233753,593,0,234653,591,0,235553,589,0,236453,586,0,237354,584,0,238855,582,0,240055,580,0,241554,578,0,242455,576,0,243954,574,0,244856,572,0,246357,570,0,247257,568,0,248458,566,0,249658,564,0,250858,562,0,252358,560,0,253559,558,0,254758,551,0,255359,4639,0,255959,4636,0,256558,535,0,257459,533,0,258659,531,0,260159,529,0,261059,527,0,262260,525,0,263760,523,0,265261,521,0,266462,519,0,267662,517,0,269463,515,0,270663,513,0,272462,511,0,273963,509,0,275162,507,0,276663,505,0,277563,503,0,278463,501,0,280263,499,0,281762,497,0,282663,495,0,283563,493,0,284462,491,0,285663,489,0,286562,487,0,287162,485,0,287763,483,1,288363,481,0,289262,479,0,290162,476,0,291063,474,0,291663,472,0,292563,470,0,293763,467,0,294663,465,0,295563,459,1,296163,4535,100,296764,428,27,297364,4511,17,297964,4502,54,298564,4493,37,299164,4485,53,299764,4476,9,300364,4467,5,300964,4459,0,301563,347,2,302163,345,4,303064,342,0,303963,339,0,304563,337,0,305163,335,0,305764,332,0,306364,330,0,307264,328,0,307864,326,0,308464,324,0,309364,322,0,309964,320,0,310865,317,0,311765,315,0,312665,313,0,313266,311,0,313865,309,0,315066,306,0,315966,304,0,316567,302,0,317467,300,0,318067,298,0,318966,296,0,320167,294,0,321067,292,0,321666,290,0,322568,288,0,323468,286,0,324369,284,0,324969,282,0,325569,280,0,326169,278,0,327069,276,0,327969,274,0,328569,271,0,329169,269,0,330068,266,0,330668,264,0,331270,262,0,332469,260,0,333370,257,0,334270,254,0,335470,252,0,336372,250,0,336973,247,0,337873,245,0,338473,243,0,339073,241,0,339973,239,0,340872,237,0,341772,235,0,342673,233,0,343573,231,0,344775,229,0,345675,227,0,346574,225,0,347175,222,0,348075,220,0,348976,218,0,349876,216,0,350778,214,0,351378,212,0,352278,210,0,353478,208,0,354379,206,0,355279,204,0,356179,202,0,356779,200,0,357979,198,0,358879,196,0,359779,194,0,360979,192,0,361578,190,0,362479,188,0,363679,186,0,364278,184,0,365179,182,0,366078,180,0,366979,178,0,367879,176,0,368779,174,0,369679,172,0,370279,170,0,370878,168,0,371779,164,0,372679,162,0,373579,160,0,374478,158,0,374858,157,0,374867,156,0,375079,151,0,404480,906,0,465081,785,0,519398,628,0,584808,412,0,638229,269,0,686842,4649,0,745961,294,0,-1769405624,1770196308,793,-1769405619,1770229318,724,846798,664,0,858799,618,0,880399,586,0,897504,545,0,907709,410,0,920611,372,0,931111,335,0,937414,315,0,942813,299,0,948817,283,0,955118,266,0,961421,249,0,967425,233,0,974024,217,0,980027,200,0,985427,702,0,991727,900,2,1000428,883,4,1011232,866,0,1019335,850,0,1027140,834,0,1034339,4909,0,1042442,795,0,1050845,778,0,1060448,762,0,1069150,744,0,1074851,728,0,1081151,710,0,1087451,694,1,1092851,678,0,1097951,662,0,1102752,646,0,1106652,632,0,1109954,624,0,1113554,615,0,1118055,4703,0,1120455,4691,0,1123755,580,0,1128858,571,0,1134558,563,0,1141159,555,0,1147159,547,0,1153759,538,0,1157959,530,0,1161259,521,0,1165459,513,0,1169660,505,0,1173260,496,0,1177460,487,0,1182561,479,0,1186164,471,0,1190665,463,0,1194566,455,0,1197569,4526,0,1200269,412,0,1202669,398,0,1205069,385,0,1208070,376,0,1212273,367,0,1214974,356,0,1218275,348,0,1220977,340,0,1224280,332,0,1227581,324,0,1230883,316,0,1234184,308,0,1237786,300,0,1240789,292,0,1243791,284,0,1247091,276,0,1249493,268,0,1252494,260,0,1255194,252,0,1257895,244,0,1260596,236,0,1263598,227,0,1266899,218,0,1269299,209,0,1271700,201,0,1275001,191,0,1277701,183,0,1280401,175,0,1282802,4259,0,1285201,4238,0,1287602,343,0,1290003,722,0,1292403,962,0,1296004,999,0,1297805,995,0,1299605,991,0,1301106,987,0,1303206,983,0,1304706,979,0,1306507,975,0,1308606,971,0,1310407,967,0,1312507,963,0,1314608,959,0,1317010,955,0,1319710,951,0,1322111,947,0,1324812,943,0,1326911,938,0,1328712,933,0,1330512,929,0,1332613,5015,0,1333813,4993,0,1335013,4970,0,1336213,4949,0,1337413,4929,0,1338613,4906,0,1339813,4885,13,1341013,4864,3,1342214,4844,0,1343414,735,0,1345514,731,0,1347914,727,0,1349114,723,0,1350314,719,0,1352415,715,0,1354815,711,0,1356915,707,0,1359315,703,0,1362016,699,0,1364417,694,0,1365917,687,0,1367717,683,0,1370117,679,0,1372217,675,0,1374916,671,0,1377916,667,0,1380618,663,0,1383319,659,0,1385120,655,0,1386620,651,0,1388720,647,0,1390520,643,0,1392319,639,0,1394420,635,0,1396220,631,0,1398620,627,0,1401020,623,0,1403420,619,0,1406120,615,0,1408519,611,0,1410020,607,0,1411519,603,0,1413620,599,0,1415419,594,9,1417820,589,0,1420219,585,0,1422919,581,0,1425620,573,0,1427419,569,0,1428920,565,0,1431020,561,0,1433120,557,0,1434919,553,0,1437919,548,0,1440320,544,0,1442720,540,0,1444521,535,0,1446321,531,0,1448721,527,0,1450221,523,0,1452623,519,0,1455022,515,0,1455923,4605,0,1456523,4602,0,1457123,4600,0,1457723,496,0,1458323,494,0,1459523,492,0,1460123,490,0,1461323,488,0,1462223,486,0,1463124,484,0,1464324,482,0], [[0.000178, 0.000243, 0.000149, 0.000166, 0, 0.000106, 0.000155], 500]);
	// RestoreCopiedHistoryInternal(1770870848, [0,480,0,1201,478,0,2400,476,0,3600,474,0,5102,471,0,6304,469,0,7805,467,0,9006,464,0,10506,462,0,12305,460,0,13807,458,0,15608,456,0,16809,454,0,18310,452,0,19809,450,0,21609,448,0,23411,446,0,24611,444,0,25812,442,0,26712,440,0,27612,438,0,28213,436,0,29113,434,0,29714,432,0,30614,429,4,31514,426,0,32114,424,0,33315,422,0,33915,420,0,34817,417,3,35418,415,0,36018,413,2,36919,411,0,37520,409,0,38420,407,0,39020,405,0,39921,403,4,40521,401,0,41120,399,0,41720,397,0,42322,395,0,42922,393,0,44123,391,0,45023,389,0,45623,387,4,46223,385,0,47122,383,0,47723,381,0,48625,379,0,50360,4651,0,50960,4640,0,51560,4629,0,52160,4614,100,52760,4606,22,53360,4599,9,53960,4590,11,54560,4582,11,55160,4574,4,55760,4565,9,57947,730,0,58839,727,0,59738,724,8,60339,722,0,60939,720,0,61839,717,0,62439,714,0,63039,712,0,63638,708,0,64540,706,0,65439,703,0,66040,701,0,66939,699,0,67539,697,0,68140,695,0,68740,693,0,69339,691,0,70240,688,0,70840,686,0,71441,684,0,72041,682,0,72942,680,0,73842,678,0,74442,676,0,75042,674,0,75642,672,0,76543,670,0,77143,668,0,78043,665,0,79242,663,0,79843,661,0,80443,659,0,81043,657,0,81943,654,0,83142,652,0,84042,650,0,85243,648,0,86143,646,0,87043,644,0,87942,642,0,88842,640,0,89443,638,0,90343,636,0,91243,634,0,91843,632,0,92743,630,0,93343,628,0,94244,626,0,94844,624,0,95744,622,0,96644,620,0,97544,618,0,98144,616,0,99044,614,0,99943,612,0,100843,610,0,101743,608,0,102344,606,0,103243,604,0,104144,602,0,105043,600,0,105944,598,0,107144,596,0,108344,594,0,109844,592,0,111644,590,0,112843,588,0,114644,586,0,116143,584,0,117044,582,0,118844,580,0,120045,578,0,120645,576,0,121845,574,0,122745,572,0,123945,570,0,125145,568,0,126045,565,0,126645,563,0,127545,561,0,128445,559,0,129045,557,0,129645,4637,9,130245,4629,0,130845,520,0,131445,497,0,132045,494,0,133247,492,0,135048,490,0,135949,488,0,137149,485,0,138051,483,0,139551,481,0,140451,479,0,141350,477,0,141950,474,0,142851,472,0,144050,469,0,145251,466,2,146752,464,4,148552,462,0,149753,460,0,150653,457,0,151253,454,0,151853,452,0,152453,450,0,153052,448,0,154552,446,0,155752,444,0,156953,441,0,157853,439,0,158453,437,0,159352,435,0,160554,433,0,161753,431,0,163254,429,0,164454,427,0,166254,425,0,167153,422,0,168054,420,0,169253,418,0,171053,416,0,172254,414,0,173754,403,0,174355,380,0,174954,376,0,175854,374,0,176455,372,0,177355,370,0,178254,368,0,178855,366,0,179755,364,0,180655,362,0,181255,360,0,181855,358,0,182755,356,0,183656,354,0,184555,352,0,185455,350,0,186355,348,0,186956,346,0,187857,344,0,188757,342,0,189659,340,0,190559,338,0,191459,336,0,192360,334,0,193260,332,0,194160,330,0,195062,328,0,195662,326,0,196863,324,0,197763,322,0,198665,320,0,199265,318,0,200167,316,0,200766,314,0,201967,312,0,202868,310,0,204068,308,0,204669,306,0,205569,303,0,206168,301,0,207068,299,0,207970,297,0,208570,294,0,209170,292,0,209588,290,0,210071,278,0,210298,276,0,210449,271,0,210522,270,0,210583,268,0,210672,267,0,213672,259,1,216672,251,1,219674,243,10,222975,234,1,225375,197,2,228078,188,1,231977,180,0,234678,172,0,237081,163,0,240083,155,0,243385,147,0,246687,139,0,249989,130,0,253290,121,0,255990,352,0,258390,580,0,262891,572,0,269192,564,0,274597,556,0,279398,548,0,284498,540,0,290498,531,0,294398,523,0,299453,827,0,304576,820,0,308176,811,0,311776,4892,7,314176,752,0,318976,743,0,324076,735,0,328278,727,0,333080,719,0,338481,710,0,342381,701,0,344781,4776,0,347180,664,0,350182,655,0,352881,646,0,356187,638,0,359487,630,0,363088,621,0,367592,612,0,372694,604,0,378096,596,0,381997,588,0,387099,580,0,393100,572,0,395799,540,0,399700,530,2,403901,521,0,407801,513,0,412304,504,0,416504,495,0,421603,487,0,427604,479,0,432104,4565,0,436610,460,0,442012,452,0,448314,444,0,454014,436,0,460016,428,0,463917,420,0,467517,411,0,470517,403,0,473217,4462,15,475617,4415,23,478017,4365,7,480717,250,0,483417,241,3,486118,233,0,488820,4317,1,491219,182,0,494520,173,0,498122,165,0,501423,175,0,503822,544,0,506223,896,0,508625,890,0,509826,886,0,511926,881,0,513426,877,0,514925,873,0,516727,869,0,518828,865,0,520928,861,0,523028,857,0,524229,853,0,526329,849,0,528136,845,0,529937,841,0,531738,837,0,533538,833,0,535641,829,0,537741,825,0,539842,821,0,541943,817,0,543745,813,0,545545,809,0,547345,805,0,549145,801,0,550945,797,0,552445,792,0,554544,788,0,556344,781,40,558145,4853,0,559345,4836,0,560545,4818,0,561745,4798,18,562945,4780,30,564146,663,0,565946,659,0,567146,654,0,569246,650,0,571046,646,0,572545,642,0,574046,637,3,575846,632,0,577646,627,1,579146,622,0,580946,618,0,582446,614,0,584546,610,0,586945,606,0,589046,602,0,591453,598,0,593254,594,0,595654,590,0,598654,586,0,601054,582,0,603155,578,0,605855,574,0,607954,570,0,610354,566,0,613066,562,0,615167,558,0,617869,554,0,621769,550,0,624472,546,0,627774,542,0,630175,538,0,632575,534,0,634676,530,0,636176,526,0,638876,522,0,640676,518,0,642776,514,5,645178,509,0,647576,505,0,650277,500,0,652077,496,0,654177,492,0,655977,486,1,658677,482,2,660477,478,0,662277,474,0,663477,470,0,665277,466,3,666777,462,0,669177,458,0,670979,453,0,672479,449,0,673979,445,0,675778,441,0,678781,437,0,680881,433,0,682382,4520,0,683882,414,0,685982,410,0,689583,406,0,692284,402,0,694385,398,0,696184,394,0,697986,390,0,700092,386,0,702195,382,0,703999,378,0,705800,374,0,707602,370,0,709102,366,0,710903,362,0,712403,358,0,714204,353,0,716004,349,0,717504,345,0,718705,340,0,720205,336,0,721406,331,0,723505,327,0,724706,323,0,725906,318,0,728054,556,2,728645,4637,0,729245,4628,0,729845,4619,0,730445,4609,0,731045,4598,11,731645,4589,14,732245,481,9,732845,471,0,734025,580,0,734626,578,0,735526,576,0,736126,557,0,736726,548,0,737626,546,0,738526,544,0,739426,542,0,740325,540,0,740925,538,0,741525,536,0,742126,4623,0,742726,4616,0,743326,4608,0,743926,505,0,744526,503,0,745425,501,0,746325,499,0,747225,497,0,748434,495,0,749934,493,0,750834,491,0,751735,489,0,753234,487,0,754734,485,0,755635,483,0,757134,481,0,758336,479,0,759536,477,0,760735,474,0,761636,472,0,762236,470,0,763435,468,0,764336,466,0,765536,464,0,767036,462,0,768236,460,0,769135,458,0,770336,456,0,771836,454,0,773336,452,0,774535,450,0,776035,448,0,777236,446,0,777836,444,0,778735,442,0,780236,440,0,781435,438,0,782636,435,0,784135,433,0,785036,431,0,786254,429,0,787458,427,0,789258,425,0,790458,423,0,791658,421,0,792559,419,0,793759,417,0,794959,415,0,796161,413,0,797061,411,0,798261,409,0,799162,407,0,800362,405,0,801562,403,0,802762,401,0,803962,398,0,804862,396,0], [[0.000093, 0.001597, 0.000160, 0.000083, 0.000147, 0.000134, 0.001718, 0.000120], 500]);
	// RestoreCopiedHistoryInternal(1771676910, [0,394,0,1201,392,0,2400,390,0,3601,388,0,4201,386,0,4801,384,0,5701,381,1,6301,379,0,7201,377,0,7801,375,0,8701,371,0,9600,369,0,10201,367,0,11101,364,0,11701,362,0,12601,360,0,13201,358,0,13800,356,0,14401,354,0,15001,352,0,15600,349,5,16201,345,0,17101,343,0,17700,341,0,18601,338,1,19500,334,0,20400,332,0,21301,330,0,21901,328,0,22801,326,0,23402,324,0,24306,322,0,24906,319,0,25806,317,0,26407,315,0,27007,313,0,27606,311,0,28206,309,0,29107,306,0,30007,304,0,30608,302,0,31207,300,0,32108,298,0,32708,296,0,33608,294,0,34208,292,0,34808,290,0,35708,288,0,36607,286,0,37207,284,0,38408,4374,0,39008,4364,0,39607,4356,0,40208,4347,0,40807,237,0,41708,234,0,42309,232,0,42909,230,0,43810,228,0,44410,225,0,45310,223,0,46211,221,0,46811,219,0,47710,217,0,48310,215,0,49211,213,0,49811,211,0,50718,209,0,51318,207,0,52517,205,0,53004,203,0,53054,201,0,53118,200,0,54318,4285,0,55518,181,0,56718,365,0,57917,435,0,61218,431,0,63319,427,0,65420,423,0,67820,419,0,70520,415,0,72621,411,0,74721,407,0,77420,403,0,80120,399,0,83729,395,0,86729,391,0,87929,4481,0,89128,376,0,90329,366,0,92129,361,0,93628,356,0,95130,351,0,96930,347,0,99030,341,0,100530,337,0,102330,333,0,104130,328,18,105630,324,0,107130,320,0,108629,316,0,110129,311,0,111632,307,0,112832,291,0,114032,272,0,115532,267,0,117034,262,0,118234,258,0,119434,253,0,120933,249,0,122435,197,0,123636,168,0,125136,163,0,126336,158,0,128437,154,0,129937,150,0,131438,146,0,132939,142,0,134439,138,0,135939,134,0,137140,129,0,138339,146,0,139539,331,0,140740,516,0,142540,608,0,145542,604,0,148842,600,0,150942,596,0,153351,592,0,156053,588,0,159056,584,0,162058,580,0,165058,576,0,168361,572,0,171961,568,0,174963,564,0,176462,4653,0,177663,548,0,178863,540,0,180963,536,0,183662,532,0,185462,528,0,187262,524,0,189663,520,0,191163,516,2,192363,4602,100,193564,4588,19,194763,467,0,196564,462,0,198965,458,0,200165,454,0,201364,4532,0,202565,4516,0,203765,4502,0,204965,387,0,206464,378,0,208265,374,0,210665,370,0,212466,366,0,213965,445,0,215165,630,0,216366,816,0,217865,835,0,219366,831,0,220867,827,0,222067,823,0,223569,819,0,225369,815,0,226569,811,0,228970,807,0,230470,803,0,232270,799,0,233469,795,0,235570,791,0,237070,787,0,239172,783,0,240973,779,0,243074,775,0,245176,771,0,246976,767,0,248779,763,0,250579,759,0,252680,755,0,254483,751,0,256283,747,0,258382,743,0,260483,4832,0,261683,4827,0,262883,720,0,264384,716,0,265884,712,0,267084,708,0,268284,704,0,270984,4793,21,272184,4770,22,273384,4746,19,274584,4725,0,275784,4700,8,276984,4676,0,278184,557,23,280315,826,0,280915,824,0,281816,822,0,282716,820,0,283616,818,14,284815,816,3,286016,814,0,286921,812,3,288122,809,0,289021,807,0,289921,805,0,291122,4892,0,291722,4884,0,292322,4877,0,292922,4871,0,293522,4869,0,294122,4867,0,295022,4864,0,296222,4862,0,297422,4860,0,298622,4858,0,299522,4856,0,300422,4854,0,301321,4852,0,301922,4845,0,302522,4836,0,303122,4828,0,303722,4819,0,304322,4813,0,304922,4808,0,305521,701,0,306422,699,0,308222,697,0,309422,695,0,310621,693,0,311522,691,0,312122,689,0,313623,687,0,314823,685,0,315423,683,0,316622,681,0,317823,679,0,318724,677,0,319623,675,0,320223,673,0,321124,671,0,322024,669,0,322624,667,0,323224,665,0,324124,663,0,325023,661,0,325646,659,0,326547,657,0,327447,655,0,328347,653,0,328948,651,0,329548,649,0,330448,647,0,331348,645,0,331948,643,0,332849,641,0,333749,639,0,334348,637,0,335249,635,0,336149,633,0,337049,631,0,338249,629,0,338849,627,0,340049,625,0,340950,623,0,341850,621,0,343051,619,0,343652,617,0,344852,615,0,346052,613,0,347553,611,0,348453,609,0,349353,607,0,349953,605,0,351452,603,0,352653,601,0,353253,4693,0,353853,4691,0,354453,4689,0,355052,587,0,355653,578,0,356854,576,0,357454,573,0,358354,570,3,360153,568,0,360754,566,11,361654,564,0,362554,562,0,363154,560,0,364054,558,0,364954,556,0,365554,554,0,366154,546,0,367054,544,0,367954,542,0,368854,540,0,369454,538,0,370354,4628,0,370954,4619,0,371554,4612,0,372154,4605,0,372754,4598,0,373354,4590,0,373954,4581,0,374554,476,0,375153,474,0,375753,471,0,376653,469,0,377554,467,0,378454,465,0,379354,462,0,380553,460,0,381154,458,0,381754,456,0,382654,454,0,383554,452,0,384454,450,0,385054,448,0,385954,446,0,386554,444,0,387454,442,0,388653,440,0,389854,438,0,391054,436,0,392254,434,0,392854,432,0,393754,430,0,394354,428,0,395854,426,0,397654,424,0,400353,422,0,402153,420,0,403354,418,0,404554,416,0,405154,414,0,406654,412,0,407854,410,0,408454,408,0,409953,406,0,411755,404,0,412970,402,0,414471,400,0,415672,398,0,417171,396,0,418973,394,0,420175,392,0,421375,390,0,422576,388,0,424376,386,0,426177,384,0,427977,382,0,429478,380,0,430678,378,0,431879,376,0,433079,374,0,433679,372,0,434579,370,0,435179,367,0,436079,365,0,436680,363,31,437580,361,4,438480,358,10,439080,356,0,439680,354,0,440280,352,0,440880,350,1,441480,348,0,442079,346,0,442680,343,0,443279,340,0,443881,338,0,444781,336,0,445381,334,0,445981,332,0,446581,330,0,447181,328,0,448081,326,0,448982,324,0,449581,322,0,450180,320,0,451081,318,0,451680,316,0,452281,314,0,452881,312,0,453781,310,0,454981,307,0,455580,305,5,456180,303,0,456781,301,0,457081,294,0,457381,293,0,457680,292,0,457981,291,0,458280,290,0,458580,289,0,458881,288,0,459180,287,0,459481,286,0,459780,285,0,460081,282,0,460381,4372,0,460681,4367,0,460982,4362,0,461282,4358,0,461582,4354,0,461882,4349,0,462182,4346,0,462482,4342,0,462782,4339,0,463082,4333,0,463382,4331,0,463681,4330,0,463981,4328,0,464282,4326,0,464582,227,0,464882,221,0,465482,220,0,466082,219,0,466382,218,0,466682,217,0,466982,216,0,467582,215,0,467882,214,0,468182,213,0,468482,212,0,468782,211,0,469082,210,0,469682,209,0,470281,208,0,470582,207,0,471181,206,0,471482,205,0,472082,204,0,472382,203,0,472682,202,0,472982,201,0,473281,200,0,473582,199,0,473882,198,0,474183,197,0,474483,196,0,474782,195,0,475083,193,0,475682,192,0,475983,191,0,476583,190,0,476883,189,0,477483,188,0,478083,187,0,478382,186,0,478984,185,0,479284,184,0,479884,183,0,480184,182,0,480484,181,0,481083,180,0,481384,179,0,481983,178,0,482284,177,0,482584,176,0,482884,173,0,483184,170,0,483484,202,0,483784,248,0,484084,294,0,484384,340,0,484684,386,0,484984,432,0,485283,479,0,485584,525,0,485884,571,0,486484,570,0,487084,569,0,487984,568,0,488583,567,0,489184,566,0,490084,565,0,490684,564,0,491284,563,0,491884,562,0,492484,561,0,493084,560,0,493684,559,0,494584,558,0,494883,557,0,495483,556,0,496384,555,0,496984,554,0,497284,553,0,497884,552,0,498796,551,0,499396,550,0,499996,549,0,500896,548,0], [[0.000188, 0.000186, 0.000157, 0.000166, 0.000147, 0.000078], 500]);
	// RestoreCopiedHistoryInternal(1772178706, [0,547,0,601,546,0,1503,545,0,2102,544,0,3003,543,0,3603,542,0,4504,541,0,5404,540,0,6305,539,0,6905,538,0,7806,537,0,8407,536,0,9007,535,0,9908,534,0,10508,533,0,11709,532,0,12609,531,0,13209,530,0,13809,529,0,14410,528,0,15010,527,0,15610,526,0,15910,525,0,16510,524,0,16810,523,0,17410,522,0,18010,521,0,18610,520,0,18910,519,0,19210,518,0,20110,517,0,20710,516,0,21010,515,0,22784,716,5,23084,4802,0,23384,4797,0,23684,4792,0,23984,4788,0,24284,4784,0,24584,4779,0,24884,4774,27,25184,4770,54,25484,4766,31,25784,4762,27,26084,4757,20,26384,4753,14,26684,4748,26,26984,4743,31,27284,4739,56,27584,637,0,27884,627,0,28184,623,7,28484,622,19,29084,621,10,29384,620,0,29684,619,0,29983,618,0,30284,617,0,30884,616,0,31484,615,0,31783,614,0,32084,613,0,32388,612,0,32689,611,0,33289,610,0,33588,609,0,34189,608,0,34489,606,0,34788,605,0,35089,604,0,35688,603,0,35989,602,0,36588,601,1,36889,599,0,37188,598,0,37488,597,1,37788,596,0,38089,594,0,38388,593,0,38689,592,0,39289,591,0,39589,590,0,39889,589,0,40489,588,0,40789,587,1,41089,4681,0,41389,4674,0,41689,4670,0,41989,4666,0,42289,4663,0,42589,4659,0,42889,4655,0,43189,4652,0,43491,4648,0,43792,4641,0,44091,537,0,44391,527,0,44690,526,0,45591,525,0,46191,524,0,46790,523,0,47695,522,0,48296,521,0,48595,520,0,48895,519,0,49195,518,0,49796,517,0,50396,516,0,50697,4610,0,50997,4607,0,51596,4605,0,51897,4604,0,52197,4603,0,52497,4602,0,52797,502,0,53397,501,0,53696,500,0,54297,499,0,54897,498,0,55496,497,0,55797,496,0,56697,494,0,56997,493,0,57297,492,0,57897,491,0,58197,490,0,59098,489,0,59398,488,0,59998,487,0,61199,486,0,61799,485,0,62999,484,0,63599,483,0,63899,482,0,64199,481,0,64499,480,0,64799,479,0,65099,478,0,65399,477,0,65699,476,0,66298,475,0,66898,474,0,67800,473,0,68400,472,0,68700,471,0,69299,470,0,69900,469,0,70499,468,0,71100,467,0,71699,466,0,72600,465,0,73200,464,0,73800,463,0,74400,462,0,74699,461,0,75600,460,0,76499,459,0,77100,458,0,77700,457,0,78300,456,0,78900,455,0,79500,454,0,80101,453,0,80701,452,0,81300,451,0,81901,450,0,82821,449,0,83422,448,0,84624,447,0,85825,446,0,86426,445,0,87025,444,0,87626,443,0,88226,442,0,88826,441,0,89726,440,0,90026,439,0,91228,438,0,92128,437,0,93028,436,0,93628,435,0,94228,434,0,95429,433,0,96329,432,0,96630,431,0,97531,430,0,98431,429,0,99333,428,0,100532,427,0,101133,426,0,102033,425,0,102632,424,0,103533,422,0,103833,4513,0,104133,4510,0,104733,4507,0,105033,405,0,105333,403,0,105632,402,0,105933,401,0,106533,399,0,106833,398,0,107133,397,0,107433,396,0,108033,395,0,108633,394,0,108933,392,0,109232,391,1,109833,390,1,110433,388,0,110733,387,0,111333,386,0,111632,385,0,111933,384,0,112233,383,0,112833,382,0,113133,381,0,113433,380,0,113733,377,53,114032,376,0,114333,375,0,114615,374,0,114660,372,50,114724,371,0,114779,370,18,114933,369,0,115233,367,0,115532,366,0,115833,365,0,120936,292,0,126336,274,0,131437,4317,0,137437,192,0,142237,816,0,148839,886,0,154239,857,0,162040,840,0,168942,824,0,176443,808,0,183945,792,0,191447,776,0,197147,740,0,202547,651,0,209146,624,0,215749,4689,0,220848,4635,0,225949,787,0,234049,771,0,245151,755,0,254452,732,0,264065,716,0,274269,700,0,281768,682,0,286870,4690,0,294070,535,3,302770,518,0,309070,450,0,316575,432,0,324675,415,0,334278,399,0,342701,383,0,349303,367,0,356205,351,0,362804,335,0,368205,273,1,373906,4598,0,378706,4508,0,385610,378,0,392210,4435,0,395811,4397,0,398211,270,0,400911,262,0,403611,253,0,406311,245,0,409011,236,0,411711,228,0,414711,219,0,418612,211,0,421920,203,0,425220,195,0,428822,187,0,432424,179,0,436028,171,0,439629,163,0,442930,155,0,446532,147,0,449831,139,0,452533,229,0,454934,569,1,459879,4881,32,462279,750,1,467363,911,3,470664,903,0,475466,894,0,479067,886,0,482670,878,0,486573,870,0,488973,862,0,492873,854,0,497676,846,0,498877,842,0,501278,838,0,503979,834,0,506379,830,0,508179,826,0,510882,822,0,513283,818,0,515383,814,0,518385,810,0,521086,806,0,523786,802,0,526788,798,0,529490,794,0,531892,790,0,533993,786,0,536394,782,0,537594,775,0,539394,771,0,540895,767,0,542395,763,0,543595,759,0,544794,755,10,545995,751,0,547496,746,0,548997,740,0,550798,736,0,552598,731,0,554099,727,3,555299,723,0,557999,719,0,559499,715,0,560999,710,0,562499,706,0,564299,701,0,565799,697,0,567599,692,0,568799,688,0,570599,684,0,571799,678,0,573300,674,0,574500,670,0,575700,665,0,577200,660,0,579000,656,0,580201,652,0,581402,647,0,582904,642,0,584106,638,0,585607,634,0,587107,630,0,588307,626,0,590406,622,0,592210,618,0,594010,614,0,596710,610,0,598811,606,0,602111,602,0,605411,598,0,608411,594,0,612011,590,0,615611,586,0,618915,582,0,623117,577,0,625817,573,0,627017,4650,0,628217,535,0,629416,500,0,630617,494,0,631817,480,2,633316,476,0,634817,472,0,636617,467,13,638117,462,0,639617,458,4,641719,453,0,643219,449,0,645320,4540,0,646520,434,0,648320,430,0,650720,425,0,652820,420,0,654920,415,0,657020,410,0,657921,408,0,658522,405,0,659423,403,0,660323,401,0,661223,399,0,662723,397,0,663323,395,0,664823,393,0,665423,391,0,666323,389,0,667223,387,0,667823,385,0,668723,383,0,669623,381,0,670524,379,0,671125,375,0,671725,373,0,672325,370,0,673525,367,0,674125,364,0,674725,362,0,675625,360,0,676226,358,0,677126,356,0,677726,354,0,678626,352,0,679226,350,0,680126,348,0,681027,346,0,681927,344,0,682526,342,0,683127,340,0,684327,337,0,685228,335,0,686128,333,0,686729,331,0,687929,329,0,688529,327,0,689429,325,0,690029,323,0,690929,321,0,691829,319,0,692729,317,0,693329,315,0,694229,313,0,695130,311,0,696031,309,0,696931,307,0,697831,305,0,698431,303,0,699331,301,0,700232,299,0,701132,297,0,701732,295,0,702634,293,0,703535,291,0,704434,289,0,705335,287,0,706235,285,0,707135,283,0,708335,281,0,709235,278,0,710135,276,0,711036,274,0,711636,272,0,712236,270,0,713136,267,0,713736,265,0,714636,263,0,715536,261,0,716137,259,0,716737,257,0,717637,255,0,718237,253,0,718837,251,0,719737,249,0,720338,247,0,721239,245,0,721839,242,0,722439,4328,10,723039,4320,4,723639,4305,0,724239,4289,0,724839,4272,0,725439,159,0,726040,156,0,726941,153,0,728141,151,0,728741,149,0,729342,147,0,730242,206,0,730843,298,0,731443,391,0,732043,483,0,732643,576,0,733243,668,0,733843,761,0,734328,834,0,734409,832,0,734453,830,0,734545,828,0,734623,826,0,734745,824,0,735044,821,0,735345,820,0,735726,819,0,735783,817,0,735945,814,0,736244,813,0,736545,812,0,737446,811,0,737746,810,0,738046,809,0,738646,808,0,738946,807,0,739546,806,0,740169,805,0], [[0.000071, 0.000169, 0.000225, 0.000189, 0.000192, 0.000118, 0.000452], 500]);
	// RestoreCopiedHistoryInternal(1772919202, [0,805,0,70,803,0,163,800,0,864,893,0,1162,892,0,1329,890,0,1424,886,0,1464,885,0,1764,884,0,2064,889,0,2664,888,0,3196,887,0,3221,886,0,3443,883,0,3541,880,0,3568,879,0,3588,878,0,3615,877,0,3656,876,0,3864,893,0,4764,892,0,5064,891,0,5664,890,0,6264,889,0,6865,888,0,7165,887,0,7465,886,0,7765,885,0,8066,884,0,8366,883,0,8966,882,0,9266,881,0,9866,880,0,10357,879,0,10440,876,0,10492,874,0,10519,873,0,10562,872,0,10606,871,0,10650,870,0,10767,875,0,11367,874,0,11667,872,0,11967,871,0,12567,870,0,13168,869,0,13469,868,0,14069,867,0,14969,866,0,15269,861,0,15569,860,0,15822,859,0,], [[0.000126, 0.000295], 40]);

	// $.objectStoreErase("LAST_SLOPE_DATA");
}

(:debug)
function RestoreCopiedHistoryInternal(start, readHistory, readSlopes) {
	// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
	// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	// var historyArray = $.objectStoreGet("HISTORY_ARRAY", []);
	// var history = new [HISTORY_MAX * elementSize];

	// var i;
	// for (i = 0; i < HISTORY_MAX && i < readHistory.size() / 3 && readHistory[i * 3 + TIMESTAMP] != null; i++) {
	// 	history[i * elementSize + TIMESTAMP] = start + readHistory[i * 3 + TIMESTAMP];
	// 	history[i * elementSize + BATTERY] = readHistory[i * 3 + BATTERY];
	// 	if (isSolar) {
	// 		history[i * elementSize + SOLAR] = readHistory[i * 3 + SOLAR];
	// 	}
	// }

	// historyArray.add(start);
	// $.objectStorePut("HISTORY_" + start, history);

	// $.objectStorePut("SLOPES_" + start, readSlopes);
	// $.objectStorePut("HISTORY_ARRAY", historyArray);

	// if (i == 0) {
	// 	i = 1;
	// }

	// $.objectStorePut("LAST_HISTORY_KEY", [history[(i - 1) * elementSize + TIMESTAMP], history[(i - 1) * elementSize + BATTERY], (isSolar ? history[(i - 1) * elementSize + SOLAR] : null)]);
	// $.objectStoreErase("LAST_SLOPE_DATA");
}

(:release)
function buildCopiedHistory() {
}

function dumpHistory(index) {
	// var isSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
	// var elementSize = isSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

	// Sys.println("Dumping history");
	// var historyArray = $.objectStoreGet("HISTORY_ARRAY", null);
	// if (historyArray != null && historyArray.size() > 0) {
	// 	var history = $.objectStoreGet("HISTORY_" + historyArray[index], null);
	// 	if (history != null) {
	// 		Sys.println(historyArray);
	// 		var start = history[0 + TIMESTAMP];
	// 		Sys.println(start);
	// 		Sys.print("[");
	// 		var historySize = history.size() / elementSize;
	// 		for (var i = 0; i < historySize; i++) {
	// 			if (history[i * elementSize + TIMESTAMP] != null) {
	// 				Sys.print(history[i * elementSize + TIMESTAMP] - start + "," + history[i * elementSize + BATTERY] + "," + (isSolar ? history[i * elementSize + SOLAR] : null));
	// 			}
	// 			else {
	// 				break;
	// 			}
	// 			if (i < historySize - 1) {
	// 				Sys.print(",");
	// 			}
	// 		}
	// 		Sys.println("]");
	// 	}

	// 	var slopes = $.objectStoreGet("SLOPES_" + historyArray[index], null);
	// 	Sys.println(slopes);
	// }
}
