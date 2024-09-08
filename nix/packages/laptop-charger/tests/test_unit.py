from laptop_charger.main import asyncio, check_battery_level, check_plug_on, logger, SmartStrip


# Check battery level
def test_get_battery_level():
  test_battery_level = check_battery_level()
  assert isinstance(test_battery_level, int)

# Check plug status
def test_check_plug_on():
  power_strip = SmartStrip("192.168.69.53")
  test_plug_is_on = asyncio.run(check_plug_on(power_strip, "precision"))
  assert isinstance(test_plug_is_on, bool)


# If the battery is below 30% and the state is not charging, switch to charging.
# If the battery is above 80% and the state is charging, switch off.
# Otherwise, leave as is.
