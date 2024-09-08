# Laptop Charger
A python script to check the battery level and turn on/off the charger accordingling.

## Specifically:
If the battery is below 30% and the state is not charging, switch to charging.
If the battery is above 80% and the state is charging, switch off.
Otherwise, leave as is.

This will use the [kasa python package](https://github.com/python-kasa/python-kasa) and is intended to run as a systemd service.
