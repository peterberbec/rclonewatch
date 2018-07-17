# First, this will not function as is. It's part of a much bigger script.
# rclone_watch() is called from upload() so head down there now
out=("_   " " _  " "  _ " "   _" "   -" "  - " " -  " "-   ")
printf_ds() # save the cursor position, print the date and passed value
{
        printf "\033[s$(date +"%Y/%m/%d %T") - $*"
}
printf_du() # move the cursor to previously set positition, print the date and passed value.
{
        printf "\033[u$(date +"%Y/%m/%d %T") - $*"
}
printf_d() # print the date and passed value
{
        printf "$(date +"%Y/%m/%d %T") - $*"
}
# nice to see you!
rclone_watch()
{
	PID=$!	# save the pid of the last executed function
	printf "$PID_MAIN $PID" > "$lock"	# in this case it's rclone. let's save that
	location="rclone rsync $target_text"	# this is so my clean_up function knows where my script dies
	first=1	# hack that comes later
	thinking=0	# initializing a value
	printf "\033[s"	# save our current cursor position. There IS a reason I don't use printf_ds here. I just don't remember what it is
	# oh yeah I output this to a file. This seeds the file rclone is outputting the stats to. I don't want to not have anyhting to grep
	printf "$(date +"%Y/%m/%d %H:%M:%S")\nTransferred:0 Bytes (0 Bytes/s)\nErrors: 0\nChecks: 0\nTransferred: 0\nElapsed time: 0s\n" >> "$temp"
	start_secs=$(date +%s)
	while kill -0 $PID > /dev/null 2>&1 	# display progress during transfer This loop goes until rclone dies.
	do
		check_mounts	# i check EVERY TIME THAT MY MOUNTPOINTS DONT UNMOUNT. YOU SHOULD TOO!!!!
		# Here's the guts of it. 
		# first I find the amount of data transfered.
		trans_data="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Transferred.*Bytes' | tail -n1 | awk '{ printf "%.1f%.1s", $2, $3 }')"
		# next, the rate uploaded
		trans_data_rate="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tail -n1 | tac | awk '{ print $4" "$5 }' | sed 's/(//' | sed 's/)//' | awk '{ printf "%.1f%s", $1, $2 }' | rev | cut -c7- | rev)/sec"
		# different files rclone keeps count of
		files_checked="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Checks' | tail -n1 | awk '{ print $2 }')"
		files_error="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Errors' | tail -n1 | awk '{ print $2 }')"
		files_trans="$(tac "$temp" | sed -e '/Transferred:.*Bytes/q' | tac | grep 'Transferred' | tail -n1 | awk '{ print $2 }')"
		# total files transfered
		trans_files="$((files_checked+files_error+files_trans))"
		cur_secs=$(date +%s)
		if [[ "$trans_files" == "" ]]
		then
			trans_files=0	# null, so let's assume zero
		fi
		if [ $cur_secs -eq $start_secs ]	# if we JUST started
		then
			trans_files_rate=0		# data rate will be zero
		else
			trans_files_rate=$(((trans_files*60)/(cur_secs-start_secs))) # because if we do this, we'll get a divide / 0 error
		fi
		if [[ "$trans_data" == "0.0(" ]] # if the rate is 0, it doesn't have a B, KB or GB by it.
		then
			trans_data="0.0B"
		fi
		if [[ "$trans_data_rate" == "/sec" ]] # if it's null, we want to say 0
		then
			trans_data_rate="0KB/sec"
		fi
		if [[ "$last_data" == "$trans_data" && "$last_files" == "$trans_files" && $first == 0 ]] # something silly I do while waiting for rclone to spit out more data
		then # out is an array with "_  ", " _ ", "  _" in it. I cycle through those so I know the script is running. It's stupid
			printf "\033[K ${out[thinking++]}\033[5D"	
			if [ $thinking -eq 8 ]
			then
				thinking=0
			fi
			need_clear=1	# we need to clear this from the screen before printing the next line
		else	# if rclone has outputted new data, we go here
			printf_du "$trans_files files@$trans_files_rate/min, $trans_data@$trans_data_rate\033[K"
			first=0		# once we get here, we are on our second run through
			need_clear=0
		fi
		last_data="$trans_data"		# to keep track of data being updated, we need something to compare to.
		last_files="$trans_files"
		sleep 1
	done
	if [ $need_clear -eq 1 ]
	then
		printf "\033[K"	# clear the line of text since we're done with rclone
	fi
} # head back to line 111
# Upload is passed a directory. We are going to upload that directory to my gdrive
upload()
{
	target="$1"
	if ! [ -e "$target" ]
	then
		printf_d "\"$target\" doesn't exist."
		clean_up	# clean_up is a function that removes temp files etc.
	fi
	start_secs=$(date +%s)	# for timekeeping
	check_mounts		# check_mounts is a function that makes sure the directories are mounted. I got burned badly once
				# by my mountpoint failing mid-upload. rclone silently deleted all the files because that's what I told
				# it to do.
	dest="$1"
	printf_ds "raid_6:/$target counting files..."	# printf_d, printf_ds and printf_du are a pair of printing scripts.
							# printf_d prints the date then the line
							# printf_ds sets the cursor position and prints the date and line
							# printf_du moves the cursor the the position set by printf_ds,
							# then prints the date and line.
		rclone -xq --skip-links $rclone_depth_limit size "$target" >> "$temp" 2> /dev/null & # find the number of files in our local copy
		wait_for count files in $target # wrapper function for wait. This way I know if the script dies
		total_files=$(tail -n2 "$temp" | head -n1 | awk '{ print $3 }')	# parse output of rclone above
		total_data=$(tail -n1 "$temp" | awk '{ printf "%.1f%c", $3, $4 }') # parse part 2.
	printf_du "raid_6:/$target $total_files files, $total_data\033[K\n" # we now know the size of the local files.
	# now let's do the upload
	rclone $sync $exclude -x --stats-log-level NOTICE --skip-links $rclone_depth_limit --stats ${update_time}s --checkers $checkers --transfers $transfers "$target" "$cloud_dest:$dest" >> "$temp" 2>&1 &
	# head up to the top now, see you in a bit.
	rclone_watch
	# welcome back. We've just cleared a line of text, so let's print the summary of what just happened.
	printf_du "${files_trans} files, ${trans_data}@${trans_data_rate} transferred in $(date -d @$((cur_secs-start_secs)) -u +%T).\033[K\n"
	printf_ds "$cloud_dest:/$target counting files..."	# let's see what the remote directory looks like
		rclone -xq --skip-links $rclone_depth_limit size "$cloud_dest:$target" >> "$temp" 2> /dev/null &
		wait_for_no_quit count files in $target
		total_files=$(tail -n2 "$temp" | head -n1 | awk '{ print $3 }')
		total_data=$(tail -n1 "$temp" | awk '{ printf "%.1f%c", $3, $4 }')
	printf_du "$cloud_dest:/$target $total_files files, $total_data\033[K\n"
	wait $PID # this should be a noop, but just in case we somehow got here with a BGed job, wait for it to complete.
	location=""
	PID=0
}

# and what does this output, you ask?
# here's part of the output from the current run:
2018/07/17 00:17:11 - raid_6:/etc 1696 files, 4.8M
2018/07/17 00:18:00 - 2 files, 20.2k@501.0B/sec transferred in 00:00:48.
2018/07/17 00:18:35 - gdrive:/etc 1696 files, 4.8M
2018/07/17 00:18:36 - raid_6:/root 12990 files, 687.4M
2018/07/17 00:19:18 - 132 files@188/min, 45.1M@1.1MB/sec _
