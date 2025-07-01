# BatteryMonitor

A widget that displays statistics about a Garmin's device battery as well as projecting the time until depleted. It subscribes to the Complication Publisher permission, which allows it to be laucnched directly from the compatible watch face (like Crystal-Tesla https://apps.garmin.com/apps/cfdfdbe4-a465-459d-af25-c7844b146620). Simply enter "BatteryMonitor" in the "Battery Complication Long Name" setup field of Crystal-Tesla and make a Battery field/indicator on screen. Pressing that field/indicator will launch the widget, if your device supports Complication.

It uses a linear least squares fit method to average all the recorded downtrends to find the most accurate projection until depleted.

There are 5 main views that can be viewed by swipping up or down. The first view, as well as the order and which one to show are configurable in the app Settings (see below for details). Beside a glance view, there is a summary view (default), a detail view of usage per hours, a detail view of daily usage, a graphical historical view and a projection view where the future usage trend is tagged at the end of the historical view. When charging, a popup will show up showing the battery level and the rate of increase per hour.

In the Glance and Summary view, you can choose (in Settings) to let the app determine if it's best to view 'per hour' or 'per day' (Auto) or use 'Per hour' or 'Per day'.

The default order of the panels is 1,2,3,4,5 which are respectively Summary, Hourly view, Daily view, History and a Projection view. Changing the order and removing a number while affect was is shown.

The number on the right of the gauge in the Summary view represents the time since last charged (doesn't have to be a complete charge) and the trending discharge (per hour or day). In the graph views, the left arrow represent the earliest sample time, the right arrow represent "Now' for the History view and the time the device is projected to habe a depleted battery in the Projection view. The '100=' is how long the battery is projected to last if the device was charged to 100%. The other fields are quite self explanatory.

There is enough memory to store 3000 data points, which is enough to store over 10 days of data, allowing for a better accuracy in projection.

Data points are calculated using a background process running every 5 minutes. Keep in mind that per Garmin's limitation, background processes are preventing from running when an activity is running so it's "normal" to see a 'flat line' after an abrupt drop in the graph as during the activity, no data was recorded.

**If you enjoy this this app, you can support my work with a small donation:**

https://bit.ly/sylvainga

Based on the work of JuliensLab (https://github.com/JuliensLab/Garmin-BatteryAnalyzer) and inspired by the work of dsapptech (https://apps.garmin.com/developer/b5b5e5f1-8148-42b7-9f66-f23de2625304/apps), which is missing the launch from watch face, and after asking if he could implement it and got no response, decide to build my on.

