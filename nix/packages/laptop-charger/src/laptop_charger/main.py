"""Capabilities to turn on/off kasa charger based on batter level."""
import argparse
import asyncio
import glob
import logging
import sys

from kasa import SmartStrip


logger = logging.getLogger(__name__)



def check_battery_level():
  _battery_file = f"/sys/class/power_supply/BAT*/capacity"
  battery_file = glob.glob(_battery_file)
  if len(battery_file) > 1:
    raise ValueError("There is more than one battery file!")
  with open(battery_file[0], "r") as file:
      battery_level = file.read().strip()
  logger.info(f'Laptop server battery level: {battery_level}%.')
  return int(battery_level)


async def check_plug_on(power_strip, plug_alias):
    await power_strip.update()
    for plug in power_strip.children:
        if plug.alias == plug_alias:
            is_plug_on = plug.is_on
            if is_plug_on:
              logger.info(f"Kasa plug '{plug_alias}' is on.")
            else:
              logger.info(f"Kasa plug '{plug_alias}' is off.")
            return is_plug_on


async def switch_plug(power_strip, plug_alias):
    await power_strip.update()
    for plug in power_strip.children:
        if plug.alias == plug_alias:
            if plug.is_on:
                await plug.turn_off()
            else:
                await plug.turn_on()


async def manage_charger(
  plug_alias,
  ip="192.168.69.53",
  battery_lower_threshold=40,
  battery_upper_threshold=80
):
    battery_level = check_battery_level()
    power_strip = SmartStrip(ip)
    is_plug_on = await check_plug_on(power_strip, plug_alias)
    if is_plug_on and battery_level > battery_upper_threshold:
        logger.info(f"Battery is above upper threshold of {battery_upper_threshold}% and still charging.")
        logger.info(f"Turning off plug '{plug_alias}")
        await switch_plug(power_strip, plug_alias)
        logger.info(f"Plug '{plug_alias}' turned off.")
    elif (not is_plug_on) and battery_level < battery_lower_threshold:
        logger.info(f"Battery is below lower threshold of {battery_lower_threshold}% and not charging.")
        logger.info(f"Turning on plug '{plug_alias}'..")
        await switch_plug(power_strip, plug_alias)
        logger.info(f"Plug '{plug_alias}' turned on.")
    else:
        logger.info(f"Upper threshold: {battery_upper_threshold}.")
        logger.info(f"Lower threshold: {battery_lower_threshold}.")
        logger.info(f"No changes needed to plug '{plug_alias}'.")


def main():
  # Configure logging
  logging.basicConfig(
      level=logging.INFO,  # Set the logging level to INFO
      format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
      handlers=[logging.StreamHandler(sys.stdout)]  # Ensure logs are sent to stdout
  )

  # Prepare arguments
  parser = argparse.ArgumentParser(description="Script to manage laptop server charging.")

  parser.add_argument(
      '--plug-alias',
      type=str,
      required=True,
      help='Name of the kasa smart strip plug alias (managed in app).'
  )
  args = parser.parse_args()

  # Run script
  asyncio.run(manage_charger(args.plug_alias))
