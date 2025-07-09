# BatteryMonitor

A widget that displays statistics about a Garmin's device battery as well as projecting the time until depleted and the solar intensity if the device supports that feature. It subscribes to the Complication Publisher permission, which allows it to be launched directly from the compatible watch face (like Crystal-Tesla https://apps.garmin.com/apps/cfdfdbe4-a465-459d-af25-c7844b146620). Simply enter "BatteryMonitor" in the "Battery Complication Long Name" setup field of Crystal-Tesla and make a Battery field/indicator on screen. Pressing that field/indicator will launch the widget, if your device supports Complication.

It uses a linear least squares fit method to average all the recorded downtrends to find the most accurate projection until depleted.

There are 6 main views that can be viewed by swiping up or down or using the Previous/Next buttons. The first view, as well as the order and which ones to show are configurable in the app Settings (see below for details). Outside of the glance view, there is a 'Summary' view (default), a 'Usage details per hours' view, a 'Usage details per day' view, a 'Last charge' view, a 'Graphical historical' view and a 'Projection' view where the future usage trend is tagged at the end of the historical view.

In the Glance and Summary view, you can choose (in Settings) to let the app determine if it's best to view 'per hour' or 'per day' (Auto) or statically use 'Per hour' or 'Per day'.

In the Summary view, the number on the right of the batterie gauge represents the time since the device was last charged (doesn't have to be a complete charge) and below it is the trending discharge (per hour or day).

When charging, a popup will show up showing the battery level and the rate of increase per hour. Touching the screen or pressing the Select button will toggle this display on and off.

In the graph views, the battery level is color coded. 100-50% is green, 49-30% is yellow, 29-10% is orange and below 10% is red. If the device supports solar charging, a dark red line will represent the solar intensity (in %) as seen by the device. Below the graphs, the left arrow represent the earliest sample time, the right arrow represent "Now' for the History view and the time the device is projected to have a depleted battery in the Projection view. The '100=' further down is how long the battery is projected to last if the device was charged to 100%. The other fields are quite self explanatory. Pressing Select will zoom in towards now.

The default order of the panels is 1,2,3,4,5,6 which are respectively Summary, by hour view, by day view, last charge, History and a Projection view. Changing the order and removing a number will affect was is shown and their order.

Use the Menu button to erase the history and start fresh.
 
There is enough memory to store at most 1,200 data points (it's 4 times the screen size, maxing at 1,200), Since only changed battery level are recorded, depending on how fast your device is draining, and the app's ability to average older data to make room for newer ones, you'll have data for several days if not weeks.

Data points are calculated using a background process running every 5 minutes when inactive and every minute while the Glance or main app is active.

Like all my apps, they were done by me, for me and I'm sharing them with others for free. However, 

**If you enjoy this this app, you can support my work with a small donation:**

https://bit.ly/sylvainga

Some code are based on the work of JuliensLab (https://github.com/JuliensLab/Garmin-BatteryAnalyzer) and inspired by the work of dsapptech (https://apps.garmin.com/developer/b5b5e5f1-8148-42b7-9f66-f23de2625304/apps), which is missing the launch from watch face, and after asking if he could implement it and got no response, decide to build my own, hence this app :-)

If you would like to translate the language file in your own language, contact me and we'll work on it.
 
## Changelog
V1.2.0 Added the following
- History graph can be zoomed in (towards now) by touching the screen or pressing Select.
- Bug fix in the auto font selection code. Turns out 'one size fits all' doesn't work here.
- Fixed up a few field positions

V1.1.0 The following were added
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
