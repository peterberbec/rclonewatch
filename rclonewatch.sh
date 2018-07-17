rclone_watch()
{
	PID=$!
	printf "$PID_MAIN $PID" > "$lock"
	location="rclone rsync $target_text"
	first=1
	thinking=0
	printf "\033[s"
	printf "$(date +"%Y/%m/%d %H:%M:%S")\nTransferred:0 Bytes (0 Bytes/s)\nErrors: 0\nChecks: 0\nTransferred: 0\nElapsed time: 0s\n" >> "$temp"
	start_secs=$(date +%s)
	while kill -0 $PID > /dev/null 2>&1 # display progress during transfer
	do
		check_mounts
		trans_data="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Transferred.*Bytes' | tail -n1 | awk '{ printf "%.1f%.1s", $2, $3 }')"
		trans_data_rate="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tail -n1 | tac | awk '{ print $4" "$5 }' | sed 's/(//' | sed 's/)//' | awk '{ printf "%.1f%s", $1, $2 }' | rev | cut -c7- | rev)/sec"
		files_checked="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Checks' | tail -n1 | awk '{ print $2 }')"
		files_error="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Errors' | tail -n1 | awk '{ print $2 }')"
		files_trans="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Transferred' | tail -n1 | awk '{ print $2 }')"
		trans_files="$((files_checked+files_error+files_trans))"
				cur_secs=$(date +%s)
		if [[ "$trans_files" == "" ]]
		then
			trans_files=0
		fi
		if [ $cur_secs -eq $start_secs ]
		then
			trans_files_rate=0
		else
			trans_files_rate=$(((trans_files*60)/(cur_secs-start_secs)))
		fi
		if [[ "$trans_data" == "0.0(" ]]
		then
			trans_data="0.0B"
		fi
		if [[ "$trans_data_rate" == "/sec" ]]
		then
			trans_data_rate="0KB/sec"
		fi
		if [[ "$last_data" == "$trans_data" && "$last_files" == "$trans_files" && $first == 0 ]]
		then
			printf "\033[K ${out[thinking++]}\033[5D"
			if [ $thinking -eq 8 ]
			then
				thinking=0
			fi
			need_clear=1
		else
			printf_du "$trans_files files@$trans_files_rate/min, $trans_data@$trans_data_rate\033[K"
			first=0
			need_clear=0
		fi
		last_data="$trans_data"
		last_files="$trans_files"
		sleep 1
	done
	if [ $need_clear -eq 1 ]
	then
		printf "\033[K"
	fi
}
upload()
{
target="$1"
	if ! [ -e "$target" ]
	then
		printf_d "\"$target\" doesn't exist."
		clean_up
	fi
	start_secs=$(date +%s)
	check_mounts
	dest="$1"
	printf_ds "raid_6:/$target counting files..."
		rclone -xq --skip-links $rclone_depth_limit size "$target" >> "$temp" 2> /dev/null &
		wait_for count files in $target
		total_files=$(tail -n2 "$temp" | head -n1 | awk '{ print $3 }')
		total_data=$(tail -n1 "$temp" | awk '{ printf "%.1f%c", $3, $4 }')
	printf_du "raid_6:/$target $total_files files, $total_data\033[K\n"
	rclone $sync $exclude -x --stats-log-level NOTICE --skip-links $rclone_depth_limit --stats ${update_time}s --checkers $checkers --transfers $transfers "$target" "$cloud_dest:$dest" >> "$temp" 2>&1 &
	rclone_watch
	printf_du "${files_trans} files, ${trans_data}@${trans_data_rate} transferred in $(date -d @$((cur_secs-start_secs)) -u +%T).\033[K\n"
	printf_ds "$cloud_dest:/$target counting files..."
		rclone -xq --skip-links $rclone_depth_limit size "$cloud_dest:$target" >> "$temp" 2> /dev/null &
		wait_for_no_quit count files in $target
		total_files=$(tail -n2 "$temp" | head -n1 | awk '{ print $3 }')
		total_data=$(tail -n1 "$temp" | awk '{ printf "%.1f%c", $3, $4 }')
	printf_du "$cloud_dest:/$target $total_files files, $total_data\033[K\n"
	wait $PID
	location=""
	PID=0
}
