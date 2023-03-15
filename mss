#!/usr/bin/env python
# -*- coding: utf-8 -*-

#MSS Version 1.7:
# Use sortable names for playlists
#MSS Version 1.6:
#Disable usage of /var/lib/mss/time counter
#MSS Version 1.5:
#Skip all error files.
#MSS Version 1.4:
#Fix path bug.
#MSS Version 1.3:
#Port to gstreamer.
#MSS Version 1.2:
#Work on Pygame without mpd
#MSS Version 1.1:
#Add day filter
#MSS Version 1.0:
#Stability

LOGFILE = '/var/log/mss.log'
PIDFILE = '/var/run/mss.pid'
PLAYLIST_DIR = '/var/lib/mss/playlists/'
FONOGRAMS_DIR = '/var/lib/mss/'

Daemon = True

import time, datetime, os, sys, random, threading
import pygst
pygst.require("0.10")
import gst, gobject

os.chdir("/var/lib/mss")

import db

MainSchedule=[]
DaySchedule=[]
CommandSchedule=[]
Crossfade = 0

GlobalPlaylist = []
CurentSong = 0
CurentSongElaps = 0
PlayThread = False
GlobPlay = False

player_lock = threading.Lock()
player = gst.element_factory_make("playbin", "player")
time_format = gst.Format(gst.FORMAT_TIME)

class PlayList:
	def __init__(self, _start = 0):
		self.start = _start
		self.listsongs = list()
		self.totaltime = 0
		self.one = False
		self.playx = False
		self.pref = False
	
	def GetTotalTime(self):
		for i in self.listsongs:
			self.totaltime += i[1]
		return self.totaltime


def playcmd(command):
	if command == "play":
		return True
	elif command == "play_shuffle":
		return True
	elif command == "play_shuffle_insert":
		return True
	elif command == "play_insert":
		return True
	else:
		return False

def LoadSchedule(filename="schedule.mss"):
	f = open(filename)
	try:
		for line in f:
			if line[0] == "#" or line[0] == "\n":
				continue
			SplitLine = line.split()
			try:
				StrTime = SplitLine[0]+" "+SplitLine[1]
			except:
				print time.ctime(), "This line error - skip:", line
				continue
			try:
				if "-" in SplitLine[0]:
					SplitDates = SplitLine[0].split("-")
					SplitDateStart = SplitDates[0].split("/")
					DateStart = time.strptime(SplitDateStart[0]+"/"+SplitDateStart[1]+"/"+SplitDateStart[2]+" "+SplitLine[1],"%d/%m/%Y %H:%M:%S")
					DateStart = datetime.datetime(DateStart[0], DateStart[1], DateStart[2], DateStart[3], DateStart[4], DateStart[5])
					SplitDateEnd = SplitDates[1].split("/")
					DateEnd = time.strptime(SplitDateEnd[0]+"/"+SplitDateEnd[1]+"/"+SplitDateEnd[2]+" "+SplitLine[1],"%d/%m/%Y %H:%M:%S")
					DateEnd = datetime.datetime(DateEnd[0], DateEnd[1], DateEnd[2], DateEnd[3], DateEnd[4], DateEnd[5])
					DayList = False
					if "," in SplitLine[2]:
						DayList = [int(i) for i in SplitLine[2].split(",")]
						SplitLine = SplitLine[1:]
						#print "DayList:", DayList
						#print "SplitLine:", SplitLine
					OneDayDelta = datetime.timedelta(days=1)
					SplitLine2 = SplitLine[1:]
					DaysDif = DateEnd-DateStart
					for i in xrange(DaysDif.days):
						#print "A:", DateStart.timetuple()
						if DayList:
							if DateStart.timetuple()[6] in DayList:
								SplitLine2[0] = time.mktime(DateStart.timetuple())
								MainSchedule.append(list(SplitLine2))
						else:
							SplitLine2[0] = time.mktime(DateStart.timetuple())
							MainSchedule.append(list(SplitLine2))
						
						DateStart += OneDayDelta
				else:
					LTime = time.strptime(StrTime, "%d/%m/%Y %H:%M:%S")
					SplitLine = SplitLine[1:]
					SplitLine[0] = time.mktime(LTime)
					MainSchedule.append(SplitLine)
			except:
				print time.ctime(), "This line error - skip:", line
				continue			
	finally:
			f.close()
	
	MainSchedule.sort(lambda x, y: cmp(x[0],y[0]))
	#print time.ctime(), "MainSchedule:", MainSchedule

def SetDaySchedule():
	# Get day schedule
	DayStartTime = list(time.localtime())
	DayStartTime[3] = 0
	DayStartTime[4] = 0
	DayStartTime[5] = 0
	DayStartTime = time.mktime(tuple(DayStartTime))
	DayEndTime = list(time.localtime())
	DayEndTime[3] = 23
	DayEndTime[4] = 59
	DayEndTime[5] = 59
	DayEndTime = time.mktime(tuple(DayEndTime))
	print time.ctime(), "DayStartTime:",DayStartTime,"DayEndTime:",DayEndTime
	
	for i in xrange(len(DaySchedule)):
		DaySchedule.pop()
	
	for schedule in  MainSchedule:
		if schedule[0] > DayStartTime and schedule[0] < DayEndTime:
			DaySchedule.append(schedule)
	
	for i in xrange(len(CommandSchedule)):
		CommandSchedule.pop()
	stop = True
	print time.ctime(), "CommandSchedule:", CommandSchedule
	for schedule in  DaySchedule:
		if playcmd(schedule[1]) and stop:
			CommandSchedule.append([schedule[0], "play", False])
			stop = False
		if schedule[1] == "stop" and not stop:
			CommandSchedule.append([schedule[0], "stop", False])
	print time.ctime(), "DaySchedule:", DaySchedule
	print time.ctime(), "CommandSchedule:", CommandSchedule

def LoadM3U(playlist):
	pl_file = open(PLAYLIST_DIR+playlist+".m3u")
	tmp_playlist = []
	for line in pl_file:
		if line[0] == "#":
			continue
		tmp_playlist.append(line[:-1])
	pl_file.close()
	return tmp_playlist

def GenerateDayList():
	# Get Playlists
	ListPlaylist = []
	for schedule in DaySchedule:
		if schedule[1] == "play":
			PL = PlayList(schedule[0])
			try:
				tmp_playlist = LoadM3U(schedule[2])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			for i in tmp_playlist:
				try:
					print time.ctime(), "Load time for song:", i
					PL.listsongs.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			ListPlaylist.append(PL)
		elif schedule[1] == "play_shuffle":
			PL = PlayList(schedule[0])
			try:
				tmp_playlist = LoadM3U(schedule[2])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			random.seed(time.time())
			random.shuffle(tmp_playlist)
			for i in tmp_playlist:
				try:
					print time.ctime(), "Load time for song:", i
					PL.listsongs.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			ListPlaylist.append(PL)
		elif schedule[1] == "play_file":
                        PL = PlayList(schedule[0])
			try:
				PL.listsongs.append([schedule[2], db.media_files[schedule[2]]-Crossfade])
				PL.one = True
				print  time.ctime(), "Load time for song:", schedule[2]
				ListPlaylist.append(PL)
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
		elif schedule[1] == "play_file_pref":
                        PL = PlayList(schedule[0])
			try:
				PL.listsongs.append([schedule[2], db.media_files[schedule[2]]-Crossfade])
				PL.one = True
				PL.pref = True
				print  time.ctime(), "Load time for song:", schedule[2]
				ListPlaylist.append(PL)
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
		elif schedule[1] == "play_shuffle_insert":
			PL = PlayList(schedule[0])
			try:
				tmp_playlist = LoadM3U(schedule[2])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			random.seed(time.time())
			random.shuffle(tmp_playlist)
			for i in tmp_playlist:
				try:
					print time.ctime(), "Load time for song:", i
					PL.listsongs.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			try:
				tmp_playlist = LoadM3U(schedule[3])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			random.seed(time.time())
			random.shuffle(tmp_playlist)
			try:
				PL.after_n = int(schedule[4])
			except:
				print time.ctime(), "Error command argument:", schedule[4], "skip..."
				DaySchedule.remove(schedule)
				continue
			PL.listsongs_after = []
			PL.playx = True
			for i in tmp_playlist:
				try:
					print  time.ctime(), "Load time for song:", i
					PL.listsongs_after.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			ListPlaylist.append(PL)
		elif schedule[1] == "play_reklama":
			tmp_listsongs = []
			try:
				split_time = schedule[3].split(":")
				end_time = schedule[0]+int(split_time[0])*60*60+int(split_time[1])*60+int(split_time[2])
				elaps_time = (60/int(schedule[4]))*60
				block = int(schedule[5])
				start_time = schedule[0]
				#print "END_TIME=", time.ctime(end_time)
				#print "Elaps_Time=", elaps_time
				#print "BLOCK=", block
			except:
				print time.ctime(), "Error command argument:", schedule[3], "or", schedule[4], "or", schedule[5], "skip..."
				DaySchedule.remove(schedule)
				continue
			try:
				tmp_playlist = LoadM3U(schedule[2])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			for i in tmp_playlist:
				try:
					print time.ctime(), "Load time for song:", i
					tmp_listsongs.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			n_in_list = 0
			while start_time < end_time:
				PL = PlayList(start_time)
				PL.one = True
				for i in xrange(block):
					PL.listsongs.append(tmp_listsongs[n_in_list])
					n_in_list+=1
					if n_in_list >= len(tmp_listsongs):
						n_in_list = 0
				ListPlaylist.append(PL)
				start_time += elaps_time
		elif schedule[1] == "play_insert":
			PL = PlayList(schedule[0])
			try:
				tmp_playlist = LoadM3U(schedule[2])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			for i in tmp_playlist:
				try:
					print  time.ctime(), "Load time for song:", i
					PL.listsongs.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			try:	
				tmp_playlist = LoadM3U(schedule[3])
			except:
				print time.ctime(), "Can`t load:", schedule[2], "skip..."
				DaySchedule.remove(schedule)
				continue
			random.seed(time.time())
			random.shuffle(tmp_playlist)

			try:
				PL.after_n = int(schedule[4])
			except:
				print time.ctime(), "Error command argument:", schedule[4], "skip..."
				DaySchedule.remove(schedule)
				continue
			PL.listsongs_after = []
			PL.playx = True
			for i in tmp_playlist:
				try:
					print  time.ctime(), "Load time for song:", i
					PL.listsongs_after.append([i, db.media_files[i]-Crossfade])
				except:
					print time.ctime(), "Error:", i, "not in DB."
			ListPlaylist.append(PL)
		else:
			print time.ctime(), "Error command:", schedule[1]

	
	# Generate DayList
	DayList = []
	n = 0
	for pl in ListPlaylist:
		print pl.listsongs
		stoptime = 0
		for i in DaySchedule:
			if playcmd(i[1]) and i[0]>pl.start:
				stoptime = i[0]
				break
		if stoptime == 0:
			for i in CommandSchedule:
				if i[1] == "stop" and i[0]>pl.start:
					stoptime = i[0]
					break
		NeedLength = stoptime - pl.start
		if pl.GetTotalTime() < NeedLength and not pl.one:
			tmp_n = 0
			while pl.totaltime < NeedLength:
				pl.listsongs.append(pl.listsongs[tmp_n])
				pl.totaltime += pl.listsongs[tmp_n][1]
				tmp_n += 1
		if pl.playx:
			tmp_n1, tmp_n2 = 0, 0
			while True:
				tmp_n1 += pl.after_n
				if tmp_n2 >= len(pl.listsongs_after):
					tmp_n2 = 0
				if tmp_n1 >= len(pl.listsongs):
					break
				try:
					pl.listsongs.insert(tmp_n1, pl.listsongs_after[tmp_n2])
				except:
					print time.ctime(), "Error in generate list."
				tmp_n1 += 1
				tmp_n2 += 1
		if len(DayList) == 0:
			DayList.extend(pl.listsongs)
		else:
			starttime = 0
			for i in CommandSchedule:
				if i[1] == "play" and i[0]<pl.start:
					starttime = i[0]
			
			curtime = starttime
			tmp_n = 0
			for i in DayList:
				curtime += i[1]
				if curtime > pl.start:
					break
				tmp_n += 1
			#print "UUUUU:", pl.listsongs, tmp_n
			tmp_listsongs = pl.listsongs
			tmp_listsongs.reverse()
			if pl.pref:
				for i in tmp_listsongs:
					DayList.insert(tmp_n, i)
			else:
				for i in tmp_listsongs:
					DayList.insert(tmp_n+1, i)
		
		n+=1
	
	#Erasse crap
	starttime = 0
	for i in CommandSchedule:
		if i[1] == "play":
			starttime = i[0]
	stoptime = 0
	for i in CommandSchedule:
		if i[1] == "stop":
			stoptime = i[0]
			break
	n = 0
	for i in DayList:
		if starttime > stoptime:
			break
		starttime += i[1]
		n += 1
	for i in xrange(len(DayList)-n):
		DayList.pop()
	
	#Print DayList
	file_pls = file("/var/log/mss.pls",'w')
	starttime = 0
	for i in CommandSchedule:
		if i[1] == "play":
			starttime = i[0]
	for i in DayList:
		print time.ctime(), "Playlist:", time.ctime(starttime), i[0]
		file_pls.write("Playlist:"+time.ctime(starttime)+i[0]+"\n")
		starttime += i[1]
	file_pls.close()
	#Save new m3u list
	m3u_pl = open(PLAYLIST_DIR+str(time.strftime("%Y"))+"_"+str(time.strftime("%m"))+"_"+str(time.strftime("%d"))+".m3u",'w')
	for i in DayList:
		m3u_pl.write(i[0]+"\n")
	m3u_pl.close()


def LoadAndSearch():
	global GlobPlay
	timenow = time.time()
	startplay = [False, -1]
	starttime = 0
	n = 0
	for i in CommandSchedule:
		if i[1] == "play" and i[0] < timenow:
			i[2] = True
			startplay = [True, n]
		elif i[1] == "stop" and i[0] < timenow:
			i[2] = True
			startplay = [False, -1]
		elif i[1] == "stop" and i[0] > timenow and startplay[0]:
			starttime = CommandSchedule[startplay[1]][0]
		n += 1
	playlist = LoadM3U(str(time.strftime("%Y"))+"_"+str(time.strftime("%m"))+"_"+str(time.strftime("%d")))
	del GlobalPlaylist[:]
	GlobalPlaylist.extend(playlist)
	#GlobalPlaylist = playlist
	if starttime > 0:
		global CurentSong
		global CurentSongElaps
		CurentSong = 0
		for i in playlist:
			starttime += db.media_files[i]-Crossfade
			print time.ctime(), "Search current song:",i, starttime
			if starttime > time.time():
				starttime -= db.media_files[i]
				CurentSongElaps = time.time() - starttime
				player.set_property("uri", "file://"+FONOGRAMS_DIR+i)
				player.set_state(gst.STATE_PLAYING)
				GlobPlay += True
				break
			CurentSong += 1

def ScheduleCycle():
	day = time.strftime("%d")
	global GlobPlay
	while True:
		timenow = time.time()
		for i in CommandSchedule:
			if not i[2] and i[0]<=timenow:
				if i[1] == "play":
					#pygame.mixer.music.play()
					#i[2] = True
					LoadAndSearch()
					print  time.ctime(), "Set Play!"
				elif i[1] == "stop":
					for tm in xrange(10):
						#pygame.mixer.music.set_volume(1.0-tm*0.1)
						player.set_property("volume", 1.0-tm*0.1)
						time.sleep(1)
					player.set_state(gst.STATE_NULL)
					player.set_property("volume", 1.0)
					i[2] = True
					GlobPlay *= False
					print  time.ctime(), "Set Stop!"
		if day != time.strftime("%d"):
			SetDaySchedule()
			try:
				f = open(PLAYLIST_DIR+str(time.strftime("%Y"))+"_"+str(time.strftime("%m"))+"_"+str(time.strftime("%d"))+".m3u")
				f.close()
			except:
				GenerateDayList()
			day = time.strftime("%d")
			LoadAndSearch()
			
		time.sleep(1)

class Play(threading.Thread):
	def __init__(self):
		self.work = True
		threading.Thread.__init__(self)
	def run(self):
		global CurentSong
		global FONOGRAMS_DIR
		global GlobalPlaylist
		global GlobPlay
		while self.work:
			player_lock.acquire()
			if CurentSong+1 < len(GlobalPlaylist) and GlobPlay:
				CurentSong += 1
				player.set_property("uri", "file://"+FONOGRAMS_DIR+GlobalPlaylist[CurentSong])
				player.set_state(gst.STATE_PLAYING)
				print time.ctime(),"Start play:", GlobalPlaylist[CurentSong]

class GobInit(threading.Thread):
	def __init__(self):
		threading.Thread.__init__(self)
	def run(self):
		gobject.threads_init()
		self.loop = gobject.MainLoop()
		self.loop.run()

def on_message(bus, message):
	global CurentSongElaps
	t = message.type
	if t == gst.MESSAGE_ASYNC_DONE:
		if CurentSongElaps:
			player.seek_simple(time_format, gst.SEEK_FLAG_FLUSH, CurentSongElaps*1000000000)
			CurentSongElaps = 0
	elif t == gst.MESSAGE_EOS:
		player.set_state(gst.STATE_NULL)
		player_lock.release()
	elif t == gst.MESSAGE_ERROR:
		player.set_state(gst.STATE_NULL)
		err, debug = message.parse_error()
		print time.ctime(), "Error: %s" % err, debug, "Skip file! Schedule does not work properly."
		player_lock.release()
		#sys.exit(0)

def Init():
	print time.ctime(), "Starting..."
	player_lock.acquire()
	PlayThread = Play()
	PlayThread.start()
	fakesink = gst.element_factory_make("fakesink", "fakesink")
	player.set_property("video-sink", fakesink)
	bus = player.get_bus()
	bus.add_signal_watch()
	bus.connect("message", on_message)
	gob = GobInit()
	gob.start()
	
	print time.ctime(), "Gstreamer Start."
	print time.ctime(), "Starting Schedules loaded."
	LoadSchedule()
	print time.ctime(), "Schedules loaded."
	SetDaySchedule()
	print time.ctime(), "Day schedules set."
	try:
		f = open(PLAYLIST_DIR+str(time.strftime("%Y"))+"_"+str(time.strftime("%m"))+"_"+str(time.strftime("%d"))+".m3u")
		f.close()
	except:
		GenerateDayList()
	
	LoadAndSearch()	
	ScheduleCycle()



class Log:
    """file like for writes with auto flush after each write
    to ensure that everything is logged, even during an
    unexpected exit."""
    def __init__(self, f):
        self.f = f
    def write(self, s):
        self.f.write(s)
        self.f.flush()

def main():
    #change to data directory if needed
    os.chdir("/var/lib/mss")
    #redirect outputs to a logfile
    sys.stdout = sys.stderr = Log(open(LOGFILE, 'a+'))
    #ensure the that the daemon runs a normal user
    os.setegid(0)     #set group first "pydaemon"
    os.seteuid(0)     #set user "pydaemon"
    #start the user program here:
    Init()

def DaemonMain():
    # do the UNIX double-fork magic, see Stevens' "Advanced
    # Programming in the UNIX Environment" for details (ISBN 0201563177)
    try:
        pid = os.fork()
        if pid > 0:
            # exit first parent
            sys.exit(0)
    except OSError, e:
        print >>sys.stderr, "fork #1 failed: %d (%s)" % (e.errno, e.strerror)
        sys.exit(1)

    # decouple from parent environment
    os.chdir("/")   #don't prevent unmounting....
    os.setsid()
    os.umask(0)

    # do second fork
    try:
        pid = os.fork()
        if pid > 0:
            # exit from second parent, print eventual PID before
            #print "Daemon PID %d" % pid
            open(PIDFILE,'w').write("%d"%pid)
            sys.exit(0)
    except OSError, e:
        print >>sys.stderr, "fork #2 failed: %d (%s)" % (e.errno, e.strerror)
        sys.exit(1)

    # start the daemon main loop
    main()

if __name__ == "__main__":
	if Daemon:
		DaemonMain()
	else:
		main()
