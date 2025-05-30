//Gas nozzle engine
/datum/ship_engine/gas_thruster
	name = "gas thruster"
	var/obj/machinery/atmospherics/unary/engine/nozzle

/datum/ship_engine/gas_thruster/New(var/obj/machinery/_holder)
	..()
	nozzle = _holder

/datum/ship_engine/gas_thruster/Destroy()
	nozzle = null
	. = ..()

/datum/ship_engine/gas_thruster/get_status()
	return nozzle.get_status()

/datum/ship_engine/gas_thruster/get_thrust()
	return nozzle.get_thrust()

/datum/ship_engine/gas_thruster/burn(var/power_modifier = 1)
	return nozzle.burn(power_modifier)

/datum/ship_engine/gas_thruster/set_thrust_limit(var/new_limit)
	nozzle.thrust_limit = new_limit

/datum/ship_engine/gas_thruster/get_thrust_limit()
	return nozzle.thrust_limit

/datum/ship_engine/gas_thruster/is_on()
	if(nozzle.use_power && nozzle.operable())
		if(nozzle.next_on > world.time)
			return -1
		else
			return 1
	return 0

/datum/ship_engine/gas_thruster/toggle()
	if(nozzle.use_power)
		nozzle.update_use_power(POWER_USE_OFF)
	else
		if(nozzle.blockage)
			if(nozzle.check_blockage())
				return
		nozzle.update_use_power(POWER_USE_IDLE)
		if(nozzle.stat & NOPOWER)//try again
			nozzle.power_change()
		if(nozzle.is_on())//if everything is in working order, start booting!
			nozzle.next_on = world.time + nozzle.boot_time

/datum/ship_engine/gas_thruster/can_burn()
	return nozzle.is_on() && nozzle.check_fuel()

//Actual thermal nozzle engine object

/obj/machinery/atmospherics/unary/engine
	name = "rocket nozzle"
	desc = "Simple rocket nozzle, expelling gas at hypersonic velocities to propell the ship."
	icon = 'icons/obj/ship_engine.dmi'
	icon_state = "nozzle"
	opacity = 1
	density = TRUE
	atmos_canpass = CANPASS_NEVER
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_FUEL

	use_power = POWER_USE_OFF
	power_channel = AREA_USAGE_EQUIP
	idle_power_usage = 21600 //6 Wh per tick for default 2 capacitor. Gives them a reason to turn it off, really to nerf backup battery

	component_types = list(
		/obj/item/circuitboard/unary_atmos/engine,
		/obj/item/stack/cable_coil = 30,
		/obj/item/pipe = 2)

	var/datum/ship_engine/gas_thruster/controller
	var/thrust_limit = 1	//Value between 1 and 0 to limit the resulting thrust
	var/volume_per_burn = 15 //20 litres(with bin)
	var/charge_per_burn = 36000 //10Wh for default 2 capacitor, chews through that battery power! Makes a trade off of fuel efficient vs energy efficient
	var/boot_time = 35
	var/next_on
	var/blockage
	var/exhaust_offset = 1 // for engines that are longer
	var/exhaust_width = 1 //for engines that are wider

/obj/machinery/atmospherics/unary/engine/scc_shuttle
	icon = 'icons/obj/spaceship/scc/ship_engine.dmi'
	component_types = list(
		/obj/item/circuitboard/unary_atmos/engine/scc_shuttle,
		/obj/item/stack/cable_coil = 30,
		/obj/item/pipe = 2)

/obj/machinery/atmospherics/unary/engine/scc_ship_engine
	name = "ship thruster"
	icon = 'icons/atmos/scc_ship_engine.dmi'
	icon_state = "engine_0"
	opacity = FALSE
	pixel_x = -64
	exhaust_offset = 3
	component_types = list(
		/obj/item/circuitboard/unary_atmos/engine/scc_ship,
		/obj/item/stack/cable_coil = 30,
		/obj/item/pipe = 2)

/obj/machinery/atmospherics/unary/engine/attackby(obj/item/attacking_item, mob/user)
	. = ..()
	if(default_deconstruction_screwdriver(user, attacking_item))
		return TRUE
	if(default_deconstruction_crowbar(user, attacking_item))
		return TRUE
	if(default_part_replacement(user, attacking_item))
		return TRUE

/obj/machinery/atmospherics/unary/engine/scc_ship_engine/check_blockage()
	return 0

/obj/machinery/atmospherics/unary/engine/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(mover?.movement_type & PHASING)
		return TRUE
	return FALSE

/obj/machinery/atmospherics/unary/engine/atmos_init()
	..()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(target.initialize_directions & get_dir(target,src))
			if (check_connect_types(target,src))
				node = target
				break

	update_icon()
	update_underlays()

/obj/machinery/atmospherics/unary/engine/Initialize()
	. = ..()
	controller = new(src)
	update_nearby_tiles(need_rebuild=1)

	if(length(SSshuttle.shuttle_areas) && !length(SSshuttle.shuttles_to_initialize) && SSshuttle.initialized)
		for(var/obj/effect/overmap/visitable/ship/S as anything in SSshuttle.ships)
			if(S.check_ownership(src))
				S.engines |= controller
				if(dir != S.fore_dir)
					stat |= BROKEN
				break

/obj/machinery/atmospherics/unary/engine/Destroy()
	QDEL_NULL(controller)
	update_nearby_tiles()
	. = ..()

/obj/machinery/atmospherics/unary/engine/update_icon()
	overlays.Cut()
	if(is_on())
		overlays += "nozzle_idle"

/obj/machinery/atmospherics/unary/engine/proc/get_status()
	. = list()
	.+= "Location: [get_area(src)]."
	if(stat & NOPOWER)
		.+= "<span class='average'>Insufficient power to operate.</span>"
	if(!check_fuel())
		.+= "<span class='average'>Insufficient fuel for a burn.</span>"
	if(stat & BROKEN)
		.+= "<span class='average'>Inoperable engine configuration.</span>"
	if(blockage)
		.+= "<span class='average'>Obstruction of airflow detected.</span>"

	.+= "Propellant total mass: [round(air_contents.get_mass(),0.01)] kg."
	.+= "Propellant used per burn: [round(air_contents.get_mass() * volume_per_burn * thrust_limit / air_contents.volume,0.01)] kg."
	.+= "Propellant pressure: [round(air_contents.return_pressure()/1000,0.1)] MPa."
	. = jointext(.,"<br>")

/obj/machinery/atmospherics/unary/engine/power_change()
	. = ..()
	if(stat & NOPOWER)
		update_use_power(POWER_USE_OFF)

/obj/machinery/atmospherics/unary/engine/update_use_power()
	. = ..()
	update_icon()

/obj/machinery/atmospherics/unary/engine/proc/is_on()
	return use_power && operable() && (next_on < world.time)

/obj/machinery/atmospherics/unary/engine/proc/check_fuel()
	return air_contents.total_moles > 5 // minimum fuel usage is five moles, for EXTREMELY hot mix or super low pressure

/obj/machinery/atmospherics/unary/engine/proc/get_thrust()
	if(!is_on() || !check_fuel())
		return 0
	var/used_part = volume_per_burn * thrust_limit / air_contents.volume
	. = calculate_thrust(air_contents, used_part)
	return

/obj/machinery/atmospherics/unary/engine/proc/check_blockage()
	blockage = FALSE
	var/exhaust_dir = REVERSE_DIR(dir)
	var/turf/A = get_turf(src)
	for(var/i in 1 to exhaust_offset)
		A = get_step(A, exhaust_dir)
	var/turf/B = A
	while(isturf(A) && !(isspace(A) || isopenspace(A)))
		if((B.c_airblock(A)) & AIR_BLOCKED)
			blockage = TRUE
			break
		B = A
		A = get_step(A, exhaust_dir)
	return blockage

/obj/machinery/atmospherics/unary/engine/proc/burn(var/power_modifier = 1)
	if(!is_on())
		return 0
	if(!check_fuel() || (0 < use_power_oneoff(charge_per_burn)) || check_blockage())
		audible_message(src,SPAN_WARNING("[src] coughs once and goes silent!"))
		update_use_power(POWER_USE_OFF)
		return 0

	var/datum/gas_mixture/removed = air_contents.remove_ratio(volume_per_burn * thrust_limit * power_modifier / air_contents.volume)
	if(!removed)
		return 0
	. = calculate_thrust(removed)

	var/volume_adjustment = 1

	var/obj/effect/overmap/visitable/ship/my_ship = GLOB.map_sectors["[z]"]
	if(!my_ship)
		stack_trace("No ship found for gas thruster at z-level [z].")
	else
		volume_adjustment = length(my_ship.engines)

	playsound(loc, 'sound/machines/thruster.ogg', ((50 * thrust_limit * power_modifier) / volume_adjustment ), FALSE, world.view * 4, 0.1)
	if(network)
		network.update = 1

	var/exhaust_dir = REVERSE_DIR(dir)
	var/turf/T = get_turf(src)
	for(var/i in 1 to exhaust_offset)
		T = get_step(T, exhaust_dir)
	if(T)
		T.assume_air(removed)
		new/obj/effect/engine_exhaust(T, dir, air_contents.check_combustability() && air_contents.temperature >= PHORON_MINIMUM_BURN_TEMPERATURE)

/obj/machinery/atmospherics/unary/engine/proc/calculate_thrust(datum/gas_mixture/propellant, used_part = 1)
	return round(sqrt(propellant.get_mass() * used_part * sqrt(air_contents.return_pressure()/200)),0.1)

//Exhaust effect
/obj/effect/engine_exhaust
	name = "engine exhaust"
	icon = 'icons/obj/ship_engine.dmi'
	icon_state = "nozzle_burn"
	light_color = "#00a2ff"
	anchored = 1

/obj/effect/engine_exhaust/New(var/turf/nloc, var/ndir, var/flame)
	..(nloc)
	if(flame)
		icon_state = "exhaust"
		nloc.hotspot_expose(1000,125)
		set_light(0.5, 1, 4)
	set_dir(ndir)
	spawn(20)
		qdel(src)

