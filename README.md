# BatteryMonitor

A widget that displays statistics about a Garmin's device battery as well as projecting the time until depleted. It subscribes to the Complication Publisher permission, which allows it to be laucnched directly from the compatible watch face (like Crystal-Tesla https://apps.garmin.com/apps/cfdfdbe4-a465-459d-af25-c7844b146620). Simply enter "BatteryMonitor" in the "Battery Complication Long Name" setup field of Crystal-Tesla and make a Battery field/indicator on screen. Pressing that field/indicator will launch the widget, if your device supports Complication.

It uses a linear least squares fit method to average all the recorded downtrends to find the most accurate projection until depleted.

There are 5 main views that can be viewed by swipping up or down. Beside a glance view, their is a summary view (default), a detail view of usage per hours, a detail view of daily usage, a graphical historical view and a projection view where the future usage trend is tagged at the end of the historical view. When charging, a popup will show up showing the battery level and the rate of increase per hour.

**If you enjoy this this app, you can support my work with a small donation:**

https://bit.ly/sylvainga

Based on the work of JuliensLab (https://github.com/JuliensLab/Garmin-BatteryAnalyzer)
