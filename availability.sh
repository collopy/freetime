#!/bin/bash

#Preferences
lunch=true
weekends=true
calendar="Calendar"
days=14
day_start="09:00"
day_end="17:00"
lunch_start="12:00"
lunch_end="13:00"
minimum_duration=60 #minutes

next_day () {
	date=$(gdate -d "$date + 1 day" "+%Y-%m-%d") #Go to next day
	weekday=$(gdate -d "$date" "+%A")
	if [ $weekends = true ]; then
		if [ "$weekday" = "Saturday" ] || [ "$weekday" = "Sunday" ]; then
			next_day
		fi
	fi
	free_from=$day_start
	date_printed=false
}

print_date () {
	month=$(gdate -d "$date" "+%B")
	day=$((10#$(gdate -d "$date" "+%d"))) #Remove leading zero
	if (! $first_row); then
		echo ""
	fi
	echo -n "$weekday, $month $day at "
	date_printed=true
	first_row=false
}

print_time () {
	dash_printed=false
	
	if ($date_printed); then
		echo -n ", "
	else
		print_date
	fi
	
	start_hours=$((10#$(gdate -d "$1" "+%I"))) #Remove leading zero
	start_minutes=$(gdate -d "$1" "+%M")
	end_hours=$((10#$(gdate -d "$2" "+%I"))) #Remove leading zero
	end_minutes=$(gdate -d "$2" "+%M")
	
	if [ "$start_minutes" = "00" ]; then
		echo -n "$start_hours"
	else
		echo -n "$start_hours:$start_minutes – "
		dash_printed=true
	fi
	
	if [ "$end_minutes" = "00" ]; then
		if (! $dash_printed); then
			echo -n "–"
		fi
		echo -n "$end_hours"
	else
		if (! $dash_printed); then
			echo -n " – "
		fi
		echo -n "$end_hours:$end_minutes"
	fi
}

#Override preferences with flags
while getopts 'lwc:d:s:e:S:E:m:' option; do
	case "$option" in
		l)
			lunch=!lunch #Reverse preference for lunch breaks
			;;
		w)
			weekends=!weekends #Reverse preference for lunch breaks
			;;
		c)
			calendar=${OPTARG} #Specify calendar
			;;
		d)
			days=${OPTARG} #Provide availability for specified number of days
			;;
		s)
			day_start=$(gdate -d "${OPTARG}" "+%H:%M") #Specify start time for each day
			;;
		e)
			day_end=$(gdate -d "${OPTARG}" "+%H:%M") #Specify end time for each day
			;;
		S)
			lunch_start=$(gdate -d "${OPTARG}" "+%H:%M") #Specify start time for lunch break
			;;
		E)
			lunch_end=$(gdate -d "${OPTARG}" "+%H:%M") #Specify end time for lunch break
			;;
		m)
			minimum_duration=${OPTARG} #Specify minimum duration of times available, in minutes
			;;
	esac
done

#Initialize
date=$(gdate -d today "+%Y-%m-%d")
weekday=$(gdate -d $date "+%A")
end_date=$(gdate -d "$date + $days days" "+%Y-%m-%d")
first_row=true

#Start running here
next_day #Start with tomorrow, and skip weekend days

#Look up events in Apple calendar database
events=$(icalbuddy -ic "$calendar" -iep datetime -nrd -df "%Y-%m-%d" -b "" eventsFrom:$date to:$end_date)

#List available times between events
while IFS= read -r line; do
	
	event_date=${line:0:10}
	
	while [ "$event_date" \> "$date" ] #Event on later date
	do
		if [ $(datediff -f "%M" $free_from $day_end) -ge $minimum_duration ]; then
			print_time $free_from $day_end
		fi
		next_day
	done
	
	if [ "$line" = "$date" ]; then #All-day event
		next_day
	elif [ "${line:11:1}" = "-" ]; then #Date range
		date=$(gdate -d "${line:13:10}" "+%Y-%m-%d") #Go to last day
		next_day
	elif [ "$event_date" = "$date" ]; then #Timed event on correct date
		start=${line:14:5}
		stop=${line:22:5}
		if [ "$start" \> "$free_from" ]; then
			if [ $lunch = true ] && [ "$free_from" \< "$lunch_start" ] && [ "$start" \> "$lunch_start" ]; then
				if [ $(datediff -f "%M" $free_from $lunch_start) -ge $minimum_duration ]; then
					print_time $free_from $lunch_start
				fi
				if [ "$start" \> "$lunch_end" ] && [ $(datediff -f "%M" $lunch_end $start) -ge $minimum_duration ]; then
					print_time $lunch_end $start
				fi
			elif [ $(datediff -f "%M" $free_from $start) -ge $minimum_duration ]; then
				print_time $free_from $start
			fi
		fi
		if [ ! "$stop" \< "$day_end" ]; then #Event ends at or after end of workday
			next_day
		elif [ "$stop" \> "$free_from" ]; then #Event ends after known free time
			free_from=$stop
			if [ $lunch = true ] && [ ! "$free_from" \< "$lunch_start" ] && [ "$free_from" \< "$lunch_end" ]; then #Event ends during lunch
				free_from=$lunch_end
			fi
		fi
	fi
done <<< "$events"

#List available times after all events
while [ ! "$end_date" \< "$date" ]
do
	print_time $free_from $day_end
	next_day
done

echo ""