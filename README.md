# BatteryMonitor

A widget that displays statistics about a Garmin's device battery as well as projecting the time until depleted and the solar intensity if the device supports that feature. It subscribes to the Complication Publisher permission, which allows it to be launched directly from the compatible watch face (like Crystal-Tesla https://apps.garmin.com/apps/cfdfdbe4-a465-459d-af25-c7844b146620). Simply enter "BatteryMonitor" in the "Battery Complication Long Name" setup field of Crystal-Tesla and make a Battery field/indicator on screen. Pressing that field/indicator will launch the widget, if your device supports Complication.

It uses a linear least squares fit method to average all the recorded downtrends to find the most accurate projection until depleted.

There are 5 main views that can be viewed by swiping up or down or using the Previous/Next buttons. The first view, as well as the order and which ones to show are configurable in the app Settings (see below for details). Beside a glance view, there is a summary view (default), a detail view of usage per hours, a detail view of uage per day, a graphical historical view and a projection view where the future usage trend is tagged at the end of the historical view.

In the Glance and Summary view, you can choose (in Settings) to let the app determine if it's best to view 'per hour' or 'per day' (Auto) or statically use 'Per hour' or 'Per day'.

When charging, a popup will show up showing the battery level and the rate of increase per hour.

The default order of the panels is 1,2,3,4,5 which are respectively Summary, by hour view, by day view, History and a Projection view. Changing the order and removing a number will affect was is shown and their order.

In the Summary view, the number on the right of the gauge represents the time since the device was last charged (doesn't have to be a complete charge) and below it is the trending discharge (per hour or day).

In the graph views, the battery level, just like for the battery level in data views, is color coded. 100-50% is green, 49-30% is yellow, 29-10% is orange and below 10% is red. If the device supports solar charging, a dark red line will represent the solar intensity (in %) as seen by the device. Below the graphs, the left arrow represent the earliest sample time, the right arrow represent "Now' for the History view and the time the device is projected to have a depleted battery in the Projection view. The '100=' further down is how long the battery is projected to last if the device was charged to 100%. The other fields are quite self explanatory.

There is enough memory to store 3000 data points, which is enough to store over 10 days of data, allowing for a better accuracy in projection.

Data points are calculated using a background process running every 5 minutes. Keep in mind that per Garmin's limitation, background processes are preventing from running when an activity is going so it's "normal" to see a 'flat line' after an abrupt drop in the graph as during the activity, no data was recorded. There is nothing I can do about that.

Like all my apps, they were done by me, for me and I'm sharing them with others for free. However, 

**If you enjoy this this app, you can support my work with a small donation:**

https://bit.ly/sylvainga

Some code are based on the work of JuliensLab (https://github.com/JuliensLab/Garmin-BatteryAnalyzer) and inspired by the work of dsapptech (https://apps.garmin.com/developer/b5b5e5f1-8148-42b7-9f66-f23de2625304/apps), which is missing the launch from watch face, and after asking if he could implement it and got no response, decide to build my own, hence this app :-)

## Changelog

V1.1.0 The following were added
- Added Solar data on the graph views for watch that are solar capable. 
- Battery field in the history array has been reduced from three digits precision to one digit. Three was overkill. This will reduce the size of the history array by a lot.
- Changed the way the history array is kept. Instead of dropping the last entry when the history is full, the latest half is averaged in half to leave room for more data.
- The history size is the smallest of either four times the screen width or 1200. 
- Bug fix when running the background code. Now all the accumulated history since the last time the app was viewed (glance or full view) are accounted for, not just the last one.
- Bug fix in the auto selection of fonts based on screen size.