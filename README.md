# BatteryMonitor

BatteryMonitor is a widget/app that displays statistics about a Garmin's device battery as well as projecting the time until depleted and the solar intensity if the device supports that feature. It subscribes to the Complication Publisher permission, which allows it to be launched directly from the compatible watch face (like Crystal-Tesla https://apps.garmin.com/apps/cfdfdbe4-a465-459d-af25-c7844b146620). Simply enter "BatteryMonitor" in the "Battery Complication Long Name" setup field of Crystal-Tesla and make a Battery field/indicator on screen. Pressing that field/indicator will launch the widget, if your device supports Complication.

It uses a linear least squares fit method to average all the recorded downtrends to find the most accurate projection until depleted.

There are 7 main views that can be viewed by swiping up or down or using the Previous/Next buttons. The first view, as well as the order and which ones to show are configurable in the app Settings (see below for details). Outside of the glance view, there is a 'Summary' view (default), a 'Usage details per hours' view, a 'Usage details per day' view, a 'Last charge' view, a 'Marker' view, a 'Graphical historical' view and a 'Projection' view where the future usage trend is tagged at the end of the historical view.

In the Glance and Summary view, you can choose (in Settings) to let the app determine if it's best to view 'per hour' or 'per day' (Auto) or statically use 'Per hour' or 'Per day'.

In the Summary view, the number on the right of the batterie gauge represents the time since the device was last charged (doesn't have to be a complete charge) and below it is the trending discharge (per hour or day). The gauge itself is color coded. 100-50% is green, 49-30% is yellow, 29-10% is orange and below 10% is red. That same color convention is replicated in the battery level displayed in the other views as well as the graph's color.

In the "per hour" and "per day" view, the "Since last view" represent the time since the widget/app was lauched (not just showing its glance). The "Since last charge" doesn't have to be a full charge.

In the "Last Charge" view, it tells you when did the last charge occured and to what level did it charge to.

In the Marker view, you can set two markers using the Start button or touching the screen. Once two markes are set, the time between both as well as the discharge rate between these two times will be displayed. They will also appear as white vertical lines in the graphical views.

The projection in the glance and summary view can be as simple as the discharge from the last charge or calculated using the average of all the discharges that the data has accumulated over times.

In the graph views, if the device supports solar charging, a dark red line will represent the solar intensity (in %) as seen by the device. Below the graphs, the left arrow represent the earliest sample time, the right arrow represent "Now' for the History view and the time the device is projected to have a depleted battery in the Projection view. The '100=' further down is how long the battery is projected to last if the device was charged to 100%. A blue line under the graph means that an activity was occuring during that time sample. Helpful to see how much the battery drained within an activity compared to a timeline without an activity running.

You can zoom and pan the display in the History view (not the projection). By default, when you get to that view, you'll be in View mode. That mode is shown just above the graph. Pressing the Next and Previous button as well as swipping up and down will switch to the next/previous view. Touching the screen or pressing the Start button will switch to Zoom mode. Pressing it again will switch to the Pan mode. Pressing it again will return to the View mode. In the Zoom mode, swipe left/right or use the Next/Previous button to increase/decrease the zoom level of the graph. In the Pan mode, swipe left/right or use the Next/Previous button to pan the display left/right.

In either View, Zoom or Pan mode, touching and holding the screen in the history view will show a pop up with that position's battery usage, how far ago from the right edge is that point and its date/time. Touching the screen again (no need to hold) or switching screen will make the popup disappear. 
When charging, a popup will show up showing the battery level and the rate of increase per hour. Touching the screen or pressing the Start button will toggle this display on and off, except in the History where that button hasis used to select the view, zoom and pan mode.

Use the Menu button to erase the history and start fresh.
 
Depending on the device, there could be enough memory to store 2,500 data elements (settable in Settings, depends on how much memory your device has). Since only changed battery level are recorded, depending on how fast your device is draining, you'll have data for several days if not weeks.

Data points are calculated using a background process running every 5 minutes (configurable in Settings) when inactive and every minute while the Glance (unless in Fast launch mode) or the app is active.

**Explanation on how the projection works**:
On the real device, the Garmin's projection until discharged is two fold but for both, it's basically how long will the device last if it stays in that state, be it simply being at the watchface or being in an activity. That's why you might see a time to empty of 3 days when the device is idle and this goes down to 8 hours when you select an activity with GPS. 

In this App however, the projection until empty can be a simple ratio of the battery level at last charge over the time span since last charge or it can be a complex calculations using a linear least squares fit method to average all the recorded battery downtrends. This method gets more accurate as more data is gathered. Using the 2500 data entry and 5 minutes intervals, on my watch, it can capture up to 16 days of usage. Of course, if your activity usage is random, the accuracy of the projection will suffer. 

YOU MUST LET THE APP GATHER DATA FOR SEVERAL DAYS BEFORE A MEANINGFULL PROJECTION CAN BE DISPLAYED.

CAVEAT: Using swipe gestures in a widget is something problematic, more so on some devices. The experience in the simulator and the real device can be different, as it is for my Fenix 7S Pro. Your experience may differ. If you encounter issues, send me a email through the Contact Developper/App Support on ConnectIQ and I'll see what I can do.

I beleive this app is now feature complete. Yes, I've said that many times in the few weeks since this app was first released but I can't think of something else to add to it anymore!

**Explanation of the Settings:**
*Panel Order:*
The default order of the panels is 1,2,3,4,5,6,7 which are respectively Summary, by hour view, by day view, last charge, Marker, History and a Projection view. Changing the order and removing a number will affect was is shown and their order.

*Summary projection unit:*
The app can auto select between %/hour and %/day depending on which one makes more sense or you can say to always use a specific one.

*Which projection to show in Glance:*
On the bottom line of the Glance view, it shows the projection. This projection can either be either a simple battery usage/time since last charge or calculated using the data history it has gathered.

*What mode to launch Glance in*
Options are Fast and Whole. Fast (default) shows the charge level and the projected range was seen the last time the main app ran and no new data will be processed. In the Whole mode, the projected mode is calculated on the fly and new data are processed by the glance code itself instead of waiting for the main app to run.

*Use built-in page indicator (devices with CIQ 3.4 and above)*
Newer devices have a built-in page indicator, which I find quite intrusive on my watch, but quite usable on my Edge, so you have a choice of using the built-in one or the one I added. On older device, it only uses the one I added. Default is to use the page indicated I added (a workaround for CIQ 3.4 device that doesn't like reusing a view, I think)

*What to do when history is full:*
The app can store up to 2,500 data points, at 5 minutes per data point, that's enough data for about 3.5 days, but since the battery doesn't usually drain 0.1% (resolution of the app) per 5 minutes, this can extend for quite some time. On my 7S Pro, I had 14 days of data before reaching 2,500!
However, once that limit is reached, the app can either drop the earliest 500 data points to make room for 500 more, or down sample the last 1,000 data points (ie, average two consecutive data points into one) to again, make room for 500 new data points. Using this method, you don't loose your previous data, just its granularity.

*How many elements to store:*
This app can be quite CPU intensive, especially when showing the graphs with lots of data. It's intensive enought that on some devices, at the max stored elements (5000, configurable in Settings), the app might crash with the line "Watchdog Tripped Error - Code Executed Too Long" or 'Out of Memory" in CIQ_LOG file. Lowering this value should help.

*Maximum time in msec before having to relinquish control when drawing (from 250 to 900):*
Like mentionned above, the app might crash because it took too long to do its work. This is more prevalent while drawing the graph with lots of data points. This field tells it to stop drawing and relinquish control and continue drawing when we have the control back. You'll notice when that time is reached by a small pause while drawing the graph. 

*Background Interval (in minutes):*
Like mentioned, the background process by defaults runs every 5 minutes. Although the app takes very little power when doing its background process, even less power will be used by increasing this value. However, the accuracy of the activity detection will be impacted. Entering 0 in this fields will DISABLE the background process and data will be gathered every minute while the app is running only (in glance or main view)

Like all my apps, they were done by me, for me and I'm sharing them with others for free. However, 

**If you enjoy this this app, you can support my work with a small donation:**

https://bit.ly/sylvainga

Some code are based on the work of JuliensLab (https://github.com/JuliensLab/Garmin-BatteryAnalyzer) and inspired by the work of dsapptech (https://apps.garmin.com/developer/b5b5e5f1-8148-42b7-9f66-f23de2625304/apps), which is missing the launch from watch face, and after asking if he could implement it and got no response, decide to build my own, hence this app :-)

If you would like to translate the language file in your own language, contact me and we'll work on it.

## Changelog
**V1.10.1 Is about bug fix reported through Garmin's Exception Reporting Application (ERA) viewer**
- Bug fix in handling markers while adding data to the history array and showing last charge
- Bug fix when converting old array style prior to V1.4
- Attempt to prevent an out of memory when processing lots of data from the background process

**V1.10.0 Added the following**
- Removed devices DescentG1, Enduro, Fenix6, Fenix6S, FR245, FR55 and VenuSQ from the supported list as they differiate Apps from Widgets and don't have enough allocated Widget memory to run the app. Since this app has Glance support, they can't be an App on those devices. It's limited to Widgets.
- History data now uses its own class so devices with just 32KB of Glance memory no longer crashes with a Out Of Memory error in the crash log. However, only the FAST Launch is available now for those devices. Sorry, too much stuff was added for 32KB is enough for the full experience.
- Instead of showing a "Please wait" while the Summary view is loading, it will show the Summary view but with a flashing "???" in the fields other than the battery level. This will allow to see the battery level without waiting for the other fields to be read/calculated.
- When in Glance view and Fast mode or for devices with just 32KB of Glance memory, if there is no calculated slopes yet (ie, less than 3 data points), the Glance will display "Launch app" as it's the only time slopes is going to be calculated.
- Inputs are no longer being accepted until the view is showing.
- Graph zooming level is no loger limited to 128x but dependant on the resolution of what's on display. It will stop when the minimum distance between two points is 1/10 of the screen size. This will help to precisely select where to mark a point.
- Bug fix when activities were't being flagged in the history array.

**V1.9.3 Fixed the following**
- Switched the default to use the builtin page indicator from On to Off since devices with CIQ 3.4 crashes at launch with this setting enabled. It shouldn't, but it does so unless I find why (which I haven't after several hours of troubleshooting), those devices should restrain from using the builtin page indicator, sorry. This is settable in Settings.

**V1.9.2 Added the following**
- New method of detecting last charge and last full charge that are less CPU/time intensive.
- Added a new Settings to fast load the glance view (new default) has been added. In the Fast mode, new data since the last launch will only be processed when launching the main view (data will accumulate so don't wait months to launch the main view!) and the last calculated slope will be used instead of calculating a new one (since no new data were processed).
- Increased maximum numbers of data points from 2500 to 5000 (default remains at 2500). However, this will have a performance penalty when showing the graph and might crash devices with less available memories.
- Full history array is now only built when showing the graph (that's the only time it's used for) for the first time instead of at launch. This should shorten the lauch time, especially when there is a lot of data.
- Latency reduced when switching between View/Zoom an Pan mode.
- Background color of glances now taken into consideration when writing glance numbers (so Edge device in Day mode now have black text over white background).
- Bug fix when averaging solar values of the oldest two arrays.
- Working around a bug when storing an array and close to be out of memory (hit mostly while in Glance and processing new data).

**V1.9.1 Added the following**
- Decluterred the display by trimming trailling zeros in decimal numbers.
- The "Since Last view" and "Since Last charge" will only keep three digits of precision so 123%, 12.3% and 1.23% and 0.123% is what will now be displayed.
- Bug fix, reinstated the 5 seconds screen refresh that got removed by mistake, oops.

**V1.9.0 Added the following**
- Optimized launching of app and now shows 'Please wait' while reading initial data.
- Glance view no longer hogs the display of the glance wheel. However, it can take a few seconds before our data is shown as they are loaded after the launch, it displays 'Please wait' in the mean time.
- Bug fix when erasing data.
- Added Spanish as a supported language.
- Added Russian as a supported language (thanks Andrew for your contribution).

**V1.8.4 Added the following**
- Optimization and fail safe in the building of the full history array so it doesn't crash with a "Code Executed Too Long" when we have lots of data.

**V1.8.3 Added the following**
- Bug fix while building the history array.

**V1.8.2 Added the following**
- Code optimization to prevent running out of timers.
- Code optimization in the finding the last charge and last full charge.

**V1.8.1 Added the following**
- Fixed the blank screen when viewing graphs on some devices by decoupling the graph building from the screen refresh. Now a 'Please wait' pop up will appear while the graph is being built in the background. There shouldn't be any partly drawn graph either. A graph will only be displayed once it's fully built. It's working fine on my Fenix 7S Pro and Edge 840. If you're still experiencing problem, let me know.
- Average the slopes when averaging the earliest two 500 array elements if we end up with over 10 slopes, otherwise at one point, there will be so many slopes and will take too long to calculate the average slopes and crash.
- Reduced the distance you must swipe left to activate the menu from  90% of the screen to 75%. Fingers on screen are wider than a cursor in the simulator...

**V1.8.0 Added the following**
- Holding your finger on the screen will show a popup about that specific point. Works better if you zoom in to get a more precise location under your finger, espcially on small screen like my Fenix 7S Pro. Touch the screen to make disappear.
- While the popup is shown, holding your finger on the screen again will set a marker at that point. This uses the two marker points introduced in 1.6.0. Unlikes the Marker screen though, when both markers are set, although it will also clear both original markers, a new marker will also be set.
- The marker bars are now only shown for the active markers.  

**V1.7.0 Added the following**
- Now uses the builtin page indicators for devices with CIQ 3.4 and above.
- Added a Settings to either use the builtin page indicator (if available) or the custom one this apps has. If this setting is changed, the app needs to be restarted.
- Added a Settings to either drop the earliest 500 entries when the history array is full (default) or to average every second entries of the earliest 500 and the 500 after that. This way, you don't loose the earliest 1000 data points, just its granularity is reduced by two.
- Added a Settings to relinquish controls back to the device after drawing the graph for x msec (default to 700, settable from 250 to 900). This should help reducing the crash due to too much time passed before relinquishing control.
- Changed the direction the left and right sweep to make them more intuitive. They now pan in the direction of the screen instead of doing the opposite. Same for the zoom.
- To open the menu to clear the history on a touch screen device, swipe left across the whole screen starting from the most left edge to the most right edge. This will simulate a onMenu event.
- Optimized the graph view, slope calculation codes as well as the history size calculation. Even at 2496 data elements, it doesn't crash on my Fenix 7S Pro. Devices with bigger display (more to draw) might not have the same experience. I suggest for now you reduce the data entry to 2000 elements instead of 2500.
- Crash fix for under certain conditions in a non solar devices when drawing the graphs
- Crash fix when switching to projection view while the history view was zoomed and history array was big
- Bug fix in the selection of pages to view
- Bug fix when swiping left to zoom but not in the history view

**V1.6.0 Added the following**
- A new view has been added. It sits between the charging page and history graph by default. You'll probably need to update your page layout in Settings. There are now 7 views. The new view is a 'Marker' view. You use it to mark the current time by either pressing 'Start' or touching the screen and come back later and mark a new time. Once two markers are set, the discharge rate between both markers is shown. Pressing 'Start' or touching the screen when both markers are set clears them. A vertical white line will be shown in the graphic views for the time where you've set a marker.
- A page indicator is shown on the left side of the screen to tell you which page you are viewing. After a few seconds, it fades away and reappears when you switch view again.
- Can zoom closure than one hour now

**V1.5.0 Added tge following**
- Glance mode can show projection since the last charge or using the average of all recorded discharge rate (default). Configurable in Settings
- The summary can show projection since the last charge or using the average of all recorded discharge rate (default). Switchable by pressing the Start button or touching the screen. It resets to Projection when changing view.
- The Graph history view defaults to showing data from the last full charge (if any) or one hour if less than that. However, zomming OUT while not zoomed toggle showing this or the whole captured data.
- When zooming, the zoom level is shown.
- Optimized the search for the last full charge because if you're like me, you hardly charhe to 100% and searching the whole array wasted too much time.
- The slope calculation is now decoupled from the graph update. It update at its own intervals. As data accumulates, calculating the slopes and drawing the graph can cause a "running for too long" crash.
- Graphs code optimization to only ask to draw the time span we have set instead of relying on the device's clipping ability to not draw what's outside our current time span.
- The total amount of data captured is configurable in Settings. it's a choice between, 1000, 1500, 2000 and 2500 elements. As the total amount grows, some devices might not have enough CPU power to draw the graphs with lots of elements. If the app crashes while trying to display the graph ("Watchdog Tripped Error - Code Executed Too Long" in CIQ_LOG file), try lowering this value to capture less data.
- The interval the background process runs is configurable in Settings. It defaults to 5 minutes, which is the MINIMUM allowed by Garmin. You can increase it to gather data from a longer period of time, but at a reduced precision. If you enter 0, you'll disable the background process altogheter and data will only be gathered while the app is running (Glance or main view showing) at a rate of one sample per minute and a sample is taken only if the battery level has changed.
- Debug stuff: At the Projection view, when there is no 'Charging' popup on screen, pressing Start or touching the screen five times within 5 seconds will show a debuging line at the top. Doing the same again will disable this line. This line will show the following data each separated by a '/'.
  - Size of the HistoryArrays (each array holds 500 elements, 2500 will show 5 there). This is because Glance view can only work with limited memory compared to the main app.
  - Total number of elements recorded accross all history arrays. Once the max is reached, the earliest history array of 500 elements (and its calculated slopes) is dropped to make room for newer elements.
  - Number of elements in the current history array (from 0 to 499). Once it reaches 500, a new history array will be created.
  - The 'steps' in the graphs. If above 1, the highest battery value of the next 'steps' number of elements is used and the other aren't plotted. This is used to reduce the load on the CPU and happens when there is more elements to draw than what the device can display.
  - The time it took to draw the graph in msec. The maximum time allowed for an app to run without relinquish control is around one second (1000 msec). If this valur gets close to 1000, think about reducing the size of the captured data.

**V1.4.3 Fixed a potential crash when calculating the history array size**

**V1.4.2 Added the following**
- Improves the efficiency of the app by limiting when to save data history and when to recalculate the slopes.
- Added two more zoom level, so from one to seven instead of one to five.
- Bug fix in the finding of the last charge.

**V1.4.1 Bug fixes**
- Where when not launched from Glance would not relaunch the background process when leaving the app.
- Calculation of the slopes could crash under very specific circumstances.

**V1.4.0 Added the following**
- A blue line was added under the graph to show when an activity was occuring. Helpful to see how much the battery drained within an activity compared to a timeline without an activity running.
- Redid completely how the history is stored because Glance mode can work with far less data than the app can work with and will crash once over 700 elements are stored. Now it has room for 5 arrays of 500 elements each. Only the last array is dealt with in Glance and once an array is filled, its slopes becomes static and don't need to be recalculated. This also improves efficiencies.

**V1.3.0 Added the following**
- You can now pan the history windows using a left and right swipe for a touch enabled device. For button device, press the Start button first to move into 'Pan' mode where the Next and Previous button are then used to pan the history. Press the Start button again to return to view scroll mode. When swipping right, DON'T swipe all the way from the left of the screen as this is interpreted as pushing the Back button and will close the app.

**V1.2.0 Added the following**
- History graph can be zoomed in (towards now) by touching the screen or pressing Start.
- Bug fix in the auto font selection code. Turns out 'one size fits all' doesn't work here.
- Fixed up a few field positions

**V1.1.0 The following were added**
- Added Solar data on the graph views for watch that are solar capable. 
- A new "Last Charge when" page was added and the corresponding field in the Data views has been removed to increase the size of the text on screen. That page displays the date and time the last charge ended and at what batterie level did it charge to.
- Battery field in the history array has been reduced from three digits precision to one digit. Three was overkill. This will reduce the size of the history array by a lot.
- Changed the way the history array is kept. Instead of dropping the last entry when the history is full, the latest half is averaged in half to leave room for more data.
- The history size is the smallest of either four times the screen width or 1200.
- When the app hasn't ran for a long period, the history data waiting to be processed might get too big to be transfered to the app once awaken. If this happens, the data waiting to be processed is cut in half and it retries to process it again. If it's still to big, it's cut in half again and repeat the process until the data to be processed can be transfered.
- "Flatten" the history array to save 15 bytes per data entry (more than twice of the data entry!).
- The history array is kept in memory and read/written less frequently to save processing time/battery drain.
- Bug fix when running the background code. Now all the accumulated history since the last time the app was viewed (glance or full view) are accounted for, not just the last one.
- Bug fix in the auto selection of fonts based on screen size.
- Bug fix in the short time display where there wasn't a ' ' between both fields and last field had no unit.
