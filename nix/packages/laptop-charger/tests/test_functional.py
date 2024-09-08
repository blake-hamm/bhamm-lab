import pytest

from laptop_charger.main import asyncio, check_plug_on, logger, SmartStrip, switch_plug

@pytest.mark.asyncio
async def test_switch_plug():
  # Check power strip status
  power_strip = SmartStrip("192.168.69.53")
  test_plug_is_on = await check_plug_on(power_strip, "precision")

  # Switch plug
  await switch_plug(power_strip, "precision")

  # Check power strip status
  test_plug_is_on_opposite = await check_plug_on(power_strip, "precision")
  assert test_plug_is_on != test_plug_is_on_opposite

  # Switch back
  await switch_plug(power_strip, "precision")


# If the battery is below 30% and the state is not charging, switch to charging.
# If the battery is above 80% and the state is charging, switch off.
# Otherwise, leave as is.
