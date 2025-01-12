package states;

// If you want to add your stage to the game, copy states/stages/Template.hx,
// and put your stage code there, then, on PlayState, search for
// "switch (curStage)", and add your stage to that list.

// If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
// "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
// "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
// "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
// "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for

import backend.Achievements;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Section;
import backend.Rating;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import tjson.TJSON as Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash 
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if VIDEOS_ALLOWED 
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end

import objects.Note.EventNote;
import objects.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.FunkinLua;
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if (SScript >= "3.0.0")
import tea.SScript;
#end

@:access(flixel.sound.FlxSound._sound)
@:access(openfl.media.Sound.__buffer)

class PlayState extends MusicBeatState
{
	public var tweening:Bool = false;

	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public var timeStr:String = "";
	public var stageData:StageFile;
	public var ratingHealth:Float = 0;
	public static var finishedSong:Bool = false;

	public var tempScore:String = "";

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel";

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote>;
	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health:Float = 1;
	public var smoothHealth:Float = 1;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;
	public var judgementCounter:JudgementCounter;
	public var songPercent:Float = 0;
	public var amplitudeBar:Bar;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	public var totalNotes:Int = 0;
	public var sicks:Int = 0;
	public var goods:Int = 0;
	public var bads:Int = 0;
	public var shits:Int = 0;

	public var sickPercent:Float  = 0;
	public var goodPercent:Float = 0;
	public var badPercent:Float = 0;
	public var shitPercent:Float = 0;
	public var hitPercent:Float = 0;

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var lerpScore:Float = 0;
	
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var curAmplitude:Float = 0;
	public var instAmplitude:Float = 0;
	public var vocalAmplitude:Float = 0;
	public var vocalOpponentAmplitude:Float = 0;

	public var nps:Int = 0;
	public var maxNps:Int = 0;

	public var scoreTxt:FlxText;
	public var timeTxt:FlxText;
	public var songWatermark:FlxText;
	public var scoreX:Float = 0;
	var scoreTxtTween:FlxTween;
	var iconZoomTween:FlxTween;
	var iconDadZoomTween:FlxTween;

	var gameZoomTween:FlxTween;
	var hudZoomTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	var notesHitArray:Array<Date> = [];
	var curFrames:Int = 0;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if desktop
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	public var luaArray:Array<FunkinLua> = [];
	#if LUA_ALLOWED
	private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;

	public var precacheList:Map<String, String> = new Map<String, String>();
	
	//Song Data
	public var songName:String;
	public var composer:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var vanilaUiGroup:FlxTypedGroup<FlxBasic>;
	public var psychUiGroup:FlxTypedGroup<FlxBasic>;
	public var altUiGroup:FlxTypedGroup<FlxBasic>;
	public var kadeUiGroup:FlxTypedGroup<FlxBasic>;
	public var sbUiGroup:FlxTypedGroup<FlxBasic>;
	public var altV2UiGroup:FlxTypedGroup<FlxBasic>;

	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	public var hitVal:Int = 0;
	override public function create()
	{
		//trace('Playback Rate: ' + playbackRate);
		Paths.clearStoredMemory();

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = EnginePreferences.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = EnginePreferences.getGameplaySetting('healthgain');
		healthLoss = EnginePreferences.getGameplaySetting('healthloss');
		instakillOnMiss = EnginePreferences.getGameplaySetting('instakill');
		practiceMode = EnginePreferences.getGameplaySetting('practice');
		cpuControlled = EnginePreferences.getGameplaySetting('botplay');

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		#if android
		addAndroidControls();
		MusicBeatState.androidc.visible = false;
		#end

		persistentUpdate = true;
		persistentDraw = true;

		if (SONG == null)
			SONG = Song.loadFromJson('tutorial');

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if desktop
		storyDifficultyText = Difficulty.getString();

		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1) {
			SONG.stage = StageData.vanillaSongStage(songName);
		}
		curStage = SONG.stage;

		stageData = StageData.getStageFile(curStage);
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}

		switch (songName)
		{
			case 'bopeebo' | 'fresh' | 'dad-battle':
				composer = 'Kawai Sprite';
			case 'spookeez' | 'south':
				composer = 'Kawai Sprite';
			case 'monster':
				composer = 'Kawai Sprite and Bassetfilms';
			case 'pico' | 'blammed' | 'philly' | 'philly-nice':
				composer = 'Kawai Sprite';
			case 'milf' | 'satin-panties' | 'high':
				composer = 'Kawai Sprite';
			case 'cocoa' | 'eggnog':
				composer = 'Kawai Sprite';
			case 'winter-horrorland':
				composer = 'Kawai Sprite and Bassetfilms';
			case 'senpai' | 'roses':
				composer = 'Kawai Sprite';
			case 'thorns':
				composer = 'Kawai Sprite';
			case 'ugh' | 'guns' | 'stress':
				composer = 'Kawai Sprite';
			default:
				composer = null;
		}
		
		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else {
			if (stageData.isPixelStage)
				stageUI = "pixel";
		}
		
		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new states.stages.StageWeek1(); //Week 1
			case 'spooky': new states.stages.Spooky(); //Week 2
			case 'philly': new states.stages.Philly(); //Week 3
			case 'limo': new states.stages.Limo(); //Week 4
			case 'mall': new states.stages.Mall(); //Week 5 - Cocoa, Eggnog
			case 'mallEvil': new states.stages.MallEvil(); //Week 5 - Winter Horrorland
			case 'school': new states.stages.School(); //Week 6 - Senpai, Roses
			case 'schoolEvil': new states.stages.SchoolEvil(); //Week 6 - Thorns
			case 'tank': new states.stages.Tank(); //Week 7 - Ugh, Guns, Stress
		}

		if(isPixelStage) {
			introSoundsSuffix = '-pixel';
		}

		add(gfGroup);
		add(dadGroup);
		add(boyfriendGroup);

		#if LUA_ALLOWED
		luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		// "GLOBAL" SCRIPTS
		#if LUA_ALLOWED
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'scripts/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
			{
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
			}
		#end

		// STAGE SCRIPTS
		#if LUA_ALLOWED
		startLuasNamed('stages/' + curStage + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		startHScriptsNamed('stages/' + curStage + '.hx');
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			startCharacterScripts(gf.curCharacter);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		startCharacterScripts(dad.curCharacter);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		startCharacterScripts(boyfriend.curCharacter);

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		stagesFunc(function(stage:BaseStage) stage.createPost());

		comboGroup = new FlxSpriteGroup();
		add(comboGroup);
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(noteGroup);

		switch(EnginePreferences.data.hud)
		{
			case 'Vanila':
			vanilaUiGroup = new FlxTypedGroup<FlxBasic>();
			add(vanilaUiGroup);
			case 'Psych Engine':
			psychUiGroup = new FlxTypedGroup<FlxBasic>();
			add(psychUiGroup);
			case 'Alt Engine':
			altUiGroup = new FlxTypedGroup<FlxBasic>();
			add(altUiGroup);
			case 'Kade Engine':
			kadeUiGroup = new FlxTypedGroup<FlxBasic>();
			add(kadeUiGroup);
			case 'SB Engine':
			sbUiGroup = new FlxTypedGroup<FlxBasic>();
			add(sbUiGroup);
			case 'Alt Engine V2':
			altV2UiGroup = new FlxTypedGroup<FlxBasic>();
			add(altV2UiGroup);
		}

		Conductor.songPosition = -5000 / Conductor.songPosition;
		var showTime:Bool = (EnginePreferences.data.timeBarType != 'Disabled');
		
		switch(EnginePreferences.data.hud)
		{
			case "Psych Engine":
				timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 400, "", 32);
				timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			case "Alt Engine" | "Alt Engine V2":
				timeTxt = new FlxText(180, (EnginePreferences.data.downScroll) ? FlxG.height - 26 : 19, 0, "", 24);
				timeTxt.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			case "Kade Engine":
				timeTxt = new FlxText(640 - (501 / 2), (EnginePreferences.data.downScroll) ? FlxG.height - 24 : 16, 0, "", 24);
				timeTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				timeTxt.screenCenter(X);
			}

		if(EnginePreferences.data.hud != "Vanila")
		{
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		
		if(EnginePreferences.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;

		}
		switch(EnginePreferences.data.hud)
		{
			case "Psych Engine":
				timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
				timeBar.screenCenter(X);
				timeBar.scrollFactor.set();
			case "Alt Engine" | "Alt Engine V2":
				timeBar = new Bar(160, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
				timeBar.scrollFactor.set();
				case "Kade Engine":
				timeBar = new Bar(640 - (501 / 2), (EnginePreferences.data.downScroll) ? FlxG.height - 24 : 14, 'healthBar', function() return songPercent, 0, 1);
				timeBar.screenCenter(X);
				timeBar.scrollFactor.set();
		}
		switch (EnginePreferences.data.hud) {
			case 'SB Engine' | 'Psych Engine' | 'Alt Engine' | 'Alt Engine V2':
				timeBar.alpha = 0;
				timeBar.visible = showTime;
			case 'Kade Engine':
				timeBar.alpha = 1;
				timeBar.visible = showTime;
		}

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		noteGroup.add(strumLineNotes);

		switch(EnginePreferences.data.hud)
		{
			case "Psych Engine" | "Alt Engine" | "Alt Engine V2":
			if(EnginePreferences.data.timeBarType == 'Song Name')
			{
				timeTxt.size = 24;
				timeTxt.y += 3;
			}
		}
		
		if(EnginePreferences.data.hud == "Kade Engine")
		{
		switch(EnginePreferences.data.timeBarType)
    	{
        case 'Time Left' | 'Time Elapsed':
            timeTxt.x -= 15;
        case 'Song Name':
            timeTxt.x = 0;
            timeTxt.screenCenter();
            timeTxt.y = 14;
        case 'Time Length':
            timeTxt.x -= 45;
        case 'Song Percent':
            timeTxt.x -= 10;
        case 'Time Length Percent':
            timeTxt.x -= 70;
    	}
		}

		noteGroup.add(grpNoteSplashes);

		if(EnginePreferences.data.timeBarType == 'Song Name')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		var splash:NoteSplash = new NoteSplash(100, 100);
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		opponentStrums = new FlxTypedGroup<StrumNote>();
		playerStrums = new FlxTypedGroup<StrumNote>();

		generateSong(SONG.song);

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();
				
		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!EnginePreferences.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return (EnginePreferences.data.smoothHealth) ? smoothHealth : health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();

		if(EnginePreferences.data.hud != 'Kade Engine')
			healthBar.visible = !EnginePreferences.data.hideHud;
		else
			healthBar.visible = !EnginePreferences.data.hideHud && !cpuControlled;
	
		healthBar.alpha = EnginePreferences.data.healthBarAlpha;
		reloadHealthBarColors();
		reloadTimeBarColors();

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.hasWinningIcon = EnginePreferences.data.winIcon;
		
		if(EnginePreferences.data.hud == 'Kade Engine')
			iconP1.visible = !EnginePreferences.data.hideHud && !cpuControlled;
		else
			iconP1.visible = !EnginePreferences.data.hideHud;
	
		iconP1.alpha = EnginePreferences.data.healthBarAlpha;

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.hasWinningIcon = EnginePreferences.data.winIcon;

		if(EnginePreferences.data.hud == 'Kade Engine')
			iconP2.visible = !EnginePreferences.data.hideHud && !cpuControlled;
		else
			iconP2.visible = !EnginePreferences.data.hideHud;
			
		iconP2.alpha = EnginePreferences.data.healthBarAlpha;

		var mStr:String = (composer.length > 0) ? "\nBy:" + composer : "";
		switch(EnginePreferences.data.hud)
		{
			case 'Kade Engine':
				songWatermark = new FlxText(0, (!EnginePreferences.data.downScroll) ? FlxG.height - 16 : 0, FlxG.width, StringUtil.toTitleCase(PlayState.SONG.song, "-") + " - " + StringUtil.toTitleCase(Difficulty.getString(), " "), 28);
				songWatermark.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				songWatermark.borderSize = 1;
				songWatermark.scrollFactor.set();
				songWatermark.visible = !EnginePreferences.data.hideHud && (EnginePreferences.data.timeBarType != "Song Name");
			case 'Alt Engine' | 'Alt Engine V2':
				var composerY:Float = (composer == null) ? FlxG.height - 32 : FlxG.height - 48;
				var songY:Float = (!EnginePreferences.data.downScroll) ? composerY : 0;
				songWatermark = new FlxText(0, songY, FlxG.width, StringUtil.toTitleCase(PlayState.SONG.song, "-") + ' - ' + StringUtil.toTitleCase(Difficulty.getString()) + mStr + "\nAlt Engine v: " + AppController.altEngineVersion + AppController.stage, 28);
				songWatermark.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				songWatermark.scrollFactor.set();
				songWatermark.visible = !EnginePreferences.data.hideHud && (EnginePreferences.data.timeBarType != "Song Name");
		}

		switch(EnginePreferences.data.hud)
		{
			case 'Vanila':
				scoreTxt = new FlxText(healthBar.x + healthBar.width - 190, healthBar.y + 30, 0, "", 20);
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 0;
			case 'Alt Engine V2':
				var scoreY:Float = (EnginePreferences.data.downScroll) ? -100 : FlxG.height;
				scoreTxt = new FlxText(0, scoreY, FlxG.width, "", 20);
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 1;
			case 'Kade Engine':
				scoreTxt = new FlxText(FlxG.width / 2 - 225, healthBar.y + 50, 0, "", 20);
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 1;
			default:
				var scoreY:Float = (EnginePreferences.data.downScroll) ? 0 : FlxG.height;
				scoreTxt = new FlxText(0, (EnginePreferences.data.hud != "Alt Engine V2") ? healthBar.y + 40 : scoreY, FlxG.width, "", 20);
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 1.25;
		}
		scoreTxt.scrollFactor.set();
		scoreTxt.visible = !EnginePreferences.data.hideHud;

		switch(EnginePreferences.data.judgementCounter)
		{
			case 'Counter':
				judgementCounter = new JudgementCounter(['Hits', 'Sicks', 'Goods', 'Bads', 'Shits'], [songHits, sicks, goods, bads, shits], [hitPercent, sickPercent, goodPercent, badPercent, shitPercent], [totalNotes, songHits, songHits, songHits, songHits]);
			case 'Percent':
				judgementCounter = new JudgementCounter(['Hit', 'Sick', 'Good', 'Bad', 'Shit'], [songHits, sicks, goods, bads, shits], [hitPercent, sickPercent, goodPercent, badPercent, shitPercent], [totalNotes, songHits, songHits, songHits, songHits]);
			case 'Complex':
				judgementCounter = new JudgementCounter(['Hit', 'Sick', 'Good', 'Bad', 'Shit'], [songHits, sicks, goods, bads, shits], [hitPercent, sickPercent, goodPercent, badPercent, shitPercent], [totalNotes, songHits, songHits, songHits, songHits]);
			case 'Complex (Reversed)':
				judgementCounter = new JudgementCounter(['Hits', 'Sicks', 'Goods', 'Bads', 'Shits'], [songHits, sicks, goods, bads, shits], [hitPercent, sickPercent, goodPercent, badPercent, shitPercent], [totalNotes, songHits, songHits, songHits, songHits]);
		}

		switch(EnginePreferences.data.hud)
		{
			case 'Psych Engine':
				botplayTxt = new FlxText(400, timeBar.y + 55, FlxG.width - 800, "BOTPLAY", 32);
				botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				botplayTxt.borderSize = 1.25;
				botplayTxt.scrollFactor.set();
				botplayTxt.visible = cpuControlled;
			case 'Kade Engine':
				botplayTxt = new FlxText(400, healthBar.y - 50, FlxG.width - 800, "[BOTPLAY]", 32);
				botplayTxt.setFormat(Paths.font("vcr.ttf"), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				botplayTxt.borderSize = 1.25;
				botplayTxt.scrollFactor.set();
				botplayTxt.visible = cpuControlled;
			case 'Alt Engine' | 'Alt Engine V2':
				botplayTxt = new FlxText(FlxG.width - 480, (EnginePreferences.data.downScroll) ? FlxG.height - 50 : 0, FlxG.width - 800, "[BOTPLAY]", 32);
				botplayTxt.setFormat(Paths.font("vcr.ttf"), 25, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				botplayTxt.borderSize = 1.25;
				botplayTxt.scrollFactor.set();
				botplayTxt.visible = cpuControlled;
		}

		switch(EnginePreferences.data.hud)
		{
		case 'Alt Engine' | 'Alt Engine V2':
		amplitudeBar = new Bar(FlxG.width - 230, FlxG.height / 2, 'timeBar', function() return curAmplitude, 0, 1);
		amplitudeBar.scrollFactor.set();
		amplitudeBar.angle = -90;
		}

		updateScore(false);

		switch(EnginePreferences.data.hud)
		{
			case 'Vanila':
			vanilaUiGroup.add(healthBar);
			vanilaUiGroup.add(iconP1);
			vanilaUiGroup.add(iconP2);
			vanilaUiGroup.add(scoreTxt);
			vanilaUiGroup.cameras = [camHUD];

			case 'Psych Engine':
			psychUiGroup.add(timeBar);
			psychUiGroup.add(timeTxt);
			psychUiGroup.add(healthBar);
			psychUiGroup.add(iconP1);
			psychUiGroup.add(iconP2);
			psychUiGroup.add(scoreTxt);
			psychUiGroup.add(botplayTxt);
			psychUiGroup.cameras = [camHUD];

			case 'Alt Engine':
			altUiGroup.add(timeBar);
			altUiGroup.add(timeTxt);
			altUiGroup.add(healthBar);
			altUiGroup.add(iconP1);
			altUiGroup.add(iconP2);
			altUiGroup.add(songWatermark);
			altUiGroup.add(scoreTxt);
			altUiGroup.add(judgementCounter);
			altUiGroup.add(botplayTxt);
			altUiGroup.add(amplitudeBar);

			altUiGroup.cameras = [camHUD];

			case 'Kade Engine': // in progress
			kadeUiGroup.add(timeBar);
			kadeUiGroup.add(timeTxt);
			kadeUiGroup.add(healthBar);
			kadeUiGroup.add(iconP1);
			kadeUiGroup.add(iconP2);
			kadeUiGroup.add(scoreTxt);
			kadeUiGroup.add(judgementCounter);
			kadeUiGroup.add(botplayTxt);
			kadeUiGroup.add(songWatermark);
			kadeUiGroup.cameras = [camHUD];

			case 'SB Engine': //wait sb engine access
			sbUiGroup.add(timeBar);
			sbUiGroup.add(timeTxt);
			sbUiGroup.add(healthBar);
			sbUiGroup.add(iconP1);
			sbUiGroup.add(iconP2);
			sbUiGroup.add(scoreTxt);
			sbUiGroup.add(judgementCounter);
			sbUiGroup.add(botplayTxt);
			sbUiGroup.cameras = [camHUD];

			case 'Alt Engine V2':
			altV2UiGroup.add(timeBar);
			altV2UiGroup.add(timeTxt);
			altV2UiGroup.add(healthBar);
			altV2UiGroup.add(iconP1);
			altV2UiGroup.add(iconP2);
			altV2UiGroup.add(songWatermark);
			altV2UiGroup.add(scoreTxt);
			altV2UiGroup.add(judgementCounter);
			altV2UiGroup.add(botplayTxt);
			altV2UiGroup.add(amplitudeBar);

			altV2UiGroup.cameras = [camHUD];
		}

		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];

		startingSong = true;
		
		#if LUA_ALLOWED
		for (notetype in noteTypes)
			startLuasNamed('custom_notetypes/' + notetype + '.lua');

		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');

		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		if(eventNotes.length > 1)
		{
			for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		// SONG SPECIFIC SCRIPTS
		#if LUA_ALLOWED
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'data/' + songName + '/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
			{
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
			}
		#end

		startCallback();
		RecalculateRating();

		//PRECACHING MISS SOUNDS BECAUSE I THINK THEY CAN LAG PEOPLE AND FUCK THEM UP IDK HOW HAXE WORKS
		if(EnginePreferences.data.hitsoundVolume > 0) precacheList.set('hitsound', 'sound');
		precacheList.set('missnote1', 'sound');
		precacheList.set('missnote2', 'sound');
		precacheList.set('missnote3', 'sound');

		if (PauseSubState.songName != null) {
			precacheList.set(PauseSubState.songName, 'music');
		} else if(EnginePreferences.data.pauseMusic != 'None') {
			precacheList.set(Paths.formatToSongPath(EnginePreferences.data.pauseMusic), 'music');
		}

		precacheList.set('alphabet', 'image');
		resetRPC();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		callOnScripts('onCreatePost');

		cacheCountdown();
		cachePopUpScore();
		
		for (key => type in precacheList)
		{
			//trace('Key $key is type $type');
			switch(type)
			{
				case 'image':
					Paths.image(key);
				case 'sound':
					Paths.sound(key);
				case 'music':
					Paths.music(key);
			}
		}

		super.create();
		Paths.clearUnusedMemory();
		
		CustomFadeTransition.nextCamera = camOther;
		if(eventNotes.length < 1) checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		if(generatedMusic)
		{
			if(vocals != null) vocals.pitch = value;
			if(opponentVocals != null) opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxAnimationController.globalSpeed = value;
		Conductor.safeZoneOffset = (EnginePreferences.data.safeFrames / 60) * 1000 * value;
		setOnScripts('playbackRate', playbackRate);
		return value;
	}

	public function addTextToDebug(text:String, color:FlxColor) {
		#if LUA_ALLOWED
		var newText:DebugLuaText = luaDebugGroup.recycle(DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);
		#end
	}

	public function reloadHealthBarColors() {
		if(EnginePreferences.data.originalHealthBarColors)
		{
			healthBar.setColors(FlxColor.RED, FlxColor.LIME);
		}
		else
		{
			healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
		}
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/' + name + '.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getPreloadPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getPreloadPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		{
			scriptFile = Paths.getPreloadPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}
		
		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public function startVideo(name:String)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			precacheList.set('dialogue', 'sound');
			precacheList.set('dialogueClose', 'sound');
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);
		
		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
	  #if android
	  		MusicBeatState.androidc.visible = true;
	  #end
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != FunkinLua.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			generateStaticArrows(0);
			generateStaticArrows(1);
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(EnginePreferences.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				if (gf != null && tmr.loopsLeft % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && gf.animation.curAnim != null && !gf.animation.curAnim.name.startsWith("sing") && !gf.stunned)
					gf.dance();
				if (tmr.loopsLeft % boyfriend.danceEveryNumBeats == 0 && boyfriend.animation.curAnim != null && !boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.stunned)
					boyfriend.dance();
				if (tmr.loopsLeft % dad.danceEveryNumBeats == 0 && dad.animation.curAnim != null && !dad.animation.curAnim.name.startsWith('sing') && !dad.stunned)
					dad.dance();

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (EnginePreferences.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				notes.forEachAlive(function(note:Note) {
					if(EnginePreferences.data.opponentStrums || note.mustPress)
					{
						note.copyAlpha = false;
						note.alpha = note.multAlpha;
						if(EnginePreferences.data.middleScroll && !note.mustPress)
							note.alpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(notes), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				daNote.kill();
				notes.remove(daNote, true);
				daNote.destroy();
			}
			--i;
		}
	}

	public dynamic function updateSText()
		{
				var str:String = '';
				//AE Stuff
				var formattedPercent:String = Std.string(MathUtil.truncatePercent(lerpRating, 2) + '%');
				//Other HUDS Stuff
				var ratePercent:String = (MathUtil.truncatePercent(ratingPercent, 2));
	
				final songHitsStatus = songHits == 0;
				var ratingStatus:String; (songHitsStatus) ? "N/A" : ratePercent + '% | ' + MathUtil.getRankFromNew(ratingPercent * 100);
	
				switch(EnginePreferences.data.hud)
				{
					case 'Alt Engine':
					ratingStatus = (songHitsStatus) ? "[N/A]" : formattedPercent + ' // ${ratingFC} // ${MathUtil.getRank(ratingPercent)}' + ' // ' + ratingName + " //";
					str += ratingStatus;
					case 'Psych Engine':
					ratingStatus = (songHitsStatus) ? '?' : ratingName + ' (${ratePercent}%) - ${ratingFC}';
					str += ratingStatus;
					case 'Alt Engine V2':
					ratingStatus = (songHitsStatus) ? '[N/A]' : '${formattedPercent}\n${ratingFC} - ${ratingName}\n${MathUtil.getRank(ratingPercent)}';
					str += ratingStatus;
					case 'Kade Engine':
					ratingStatus = (songHitsStatus) ? "N/A" : ratePercent + '% | ' + MathUtil.getRankFromNew(ratingPercent * 100);
					str += '${ratingStatus}';
				}
			
			// "tempScore" variable is used to prevent another memory leak, just in case
			// "\n" here prevents the text from being cut off by beat zooms
			switch(EnginePreferences.data.hud)
			{
				case 'Vanila':
					tempScore = 'Score: ${songScore}';
					scoreTxt.size = 18;
				case 'Psych Engine':
					tempScore = 'Score: ${songScore}'
					+ (!instakillOnMiss ? ' | Misses: ${songMisses}' : "")
					+ ' | Rating: ${str}';
				case 'Alt Engine':
					tempScore = '// Score: ${MathUtil.truncateFloat(lerpScore, 0)}'
					+ (!instakillOnMiss ? ' // Misses: ${songMisses}' : "")
					+ ' // Accuracy: ${str}';
					scoreTxt.size = 20;
				
					if(cpuControlled)
					{
					scoreTxt.text += ' // [BOTPLAY]';
					}
	
				case 'Alt Engine V2':
					tempScore = (!instakillOnMiss ? 'Misses: ${songMisses}' : "")
					+ (!instakillOnMiss ? '\nScore: ${MathUtil.truncateFloat(lerpScore, 0)}' : 'Score: ${MathUtil.truncateFloat(lerpScore, 0)}')
					+ (!instakillOnMiss ? '\nAccuracy: ${str}' : 'Accuracy: ${str}');
					scoreTxt.size = 20;
					scoreTxt.alignment = FlxTextAlign.RIGHT;
	
					var subScoreY:Float = (ratingFC != "" && songHits > 0) ? 625 : 660;
					var scoreY:Float = (EnginePreferences.data.downScroll) ? 0 : subScoreY;
					if(!cpuControlled)
					FlxTween.tween(scoreTxt, {y: scoreY}, 0.5, {ease: FlxEase.backInOut});
					else
					{
					FlxTween.tween(scoreTxt, {y: (EnginePreferences.data.downScroll) ? 0 : 660}, 0.5, {ease: FlxEase.backInOut});
					}
					botplayTxt.text = 'Botplay is enabled!\nScore is not saving!';
	
				case 'Kade Engine':
					var npsStr:String = (EnginePreferences.data.npsEnabled) ? "NPS: " + nps + " (Max: " + maxNps + ") | " : "";
					var ratingStr:String = (totalPlayed != 0) ? " | Accuracy: " + str : " | Accuracy: N/A";
					tempScore = npsStr
					+ "Score: " + songScore
					+ " | Combo Breaks: " + songMisses
					+ ratingStr;
			}
			scoreTxt.text = '${tempScore}';
		}

	public function updateScore(miss:Bool = false)
	{
		updateSText();

		if(EnginePreferences.data.hud != 'Vanila' || EnginePreferences.data.hud != 'Psych Engine')
		{
			if (!miss && !cpuControlled)
			{
				doScoreBop();
				judgementCounter.bop(hitVal);
			}
		}
		else
		{
			if (!miss && !cpuControlled)
			{
				doScoreBop();
			}
		}

		callOnScripts('onUpdateScore', [miss]);
	}

	function doCameraBop(gameMult:Float = 0.015, hudMult:Float = 0.03)
	{
		if(!tweening)
		{

		if(gameZoomTween != null)
			gameZoomTween.cancel();

		FlxG.camera.zoom += gameMult;
		gameZoomTween = FlxTween.tween(FlxG.camera, {zoom: defaultCamZoom}, 0.2, {
			ease: FlxEase.sineInOut, 
			onComplete: function(twn:FlxTween) {
				gameZoomTween = null;
			}
		});
		}
		if(hudZoomTween != null)
			hudZoomTween.cancel();

		camHUD.zoom += hudMult;
		hudZoomTween = FlxTween.tween(camHUD, {zoom: 1}, 0.2, {
			ease: FlxEase.sineInOut, 
			onComplete: function(twn:FlxTween) {
				hudZoomTween = null;
			}
		});
	}
	public function doScoreBop():Void {
		if(!EnginePreferences.data.scoreZoom)
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		FlxG.sound.music.pitch = playbackRate;
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			vocals.pitch = playbackRate;

			opponentVocals.time = time;
			opponentVocals.pitch = playbackRate;
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		FlxG.sound.music.volume = 0;
		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		FlxG.sound.music.pitch = playbackRate;
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		if(startOnTime > 0) setSongTime(startOnTime - 500);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		
		if(EnginePreferences.data.hud != 'Vanila')
		{
			FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
			FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		}

		#if desktop
		// Updating Discord Rich Presence (with Time Left)
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private function generateSong(dataPath:String):Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = EnginePreferences.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * EnginePreferences.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = EnginePreferences.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();

		try
			{
				if (songData.needsVoices)
				{
				var playerVocals;
				if(songData.songPostfix != null)
					playerVocals = Paths.voices(songData.song, songData.songPostfix + '-player');
				else
					playerVocals = Paths.voices(songData.song, 'player');
	
				if(vocals != null) vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));
					
				var oppVocals;
				if(songData.songPostfix != null)
					oppVocals = Paths.voices(songData.song, songData.songPostfix + '-opponent');
				else
					oppVocals = Paths.voices(songData.song, 'opponent');
	
				if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
			}
		}
		catch(e:Dynamic) {}

		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;

		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try {
			inst.loadEmbedded(Paths.inst(songData.song, (songData.songPostfix.length > 0) ? songData.songPostfix : null));
		}
		catch(e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		var noteData:Array<SwagSection>;

		// NEW SHIT
		noteData = songData.notes;

		var file:String = Paths.json(songName + '/events');
		#if MODS_ALLOWED
		if (FileSystem.exists(Paths.modsJson(songName + '/events')) || FileSystem.exists(file)) {
		#else
		if (OpenFlAssets.exists(file)) {
		#end
			var eventsData:Array<Dynamic> = Song.loadFromJson('events', songName).events;
			for (event in eventsData) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}

		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				var gottaHitNote:Bool = section.mustHitSection;

				if (songNotes[1] > 3)
				{
					gottaHitNote = !section.mustHitSection;
				}

				var oldNote:Note;
				if (unspawnNotes.length > 0)
					oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
				else
					oldNote = null;

				var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote);
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = songNotes[2];
				swagNote.gfNote = (section.gfSection && (songNotes[1]<4));
				swagNote.noteType = songNotes[3];
				if(!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]]; //Backward compatibility + compatibility with Week 7 charts

				swagNote.scrollFactor.set();

				var susLength:Float = swagNote.sustainLength;

				susLength = susLength / Conductor.stepCrochet;
				unspawnNotes.push(swagNote);

				var floorSus:Int = Math.floor(susLength);
				if(floorSus > 0) {
					for (susNote in 0...floorSus+1)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true);
						sustainNote.mustPress = gottaHitNote;
						sustainNote.gfNote = (section.gfSection && (songNotes[1]<4));
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						swagNote.tail.push(sustainNote);
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						
						sustainNote.correctionOffset = swagNote.height / 2;
						if(!PlayState.isPixelStage)
						{
							if(oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= playbackRate;
								oldNote.updateHitbox();
							}

							if(EnginePreferences.data.downScroll)
								sustainNote.correctionOffset = 0;
						}
						else if(oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.updateHitbox();
						}

						if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2; // general offset
						else if(EnginePreferences.data.middleScroll)
						{
							sustainNote.x += 310;
							if(daNoteData > 1) //Up and Right
							{
								sustainNote.x += FlxG.width / 2 + 25;
							}
						}
					}
				}

				if (swagNote.mustPress)
				{
					swagNote.x += FlxG.width / 2; // general offset
				}
				else if(EnginePreferences.data.middleScroll)
				{
					swagNote.x += 310;
					if(daNoteData > 1) //Up and Right
					{
						swagNote.x += FlxG.width / 2 + 25;
					}
				}

				if(!noteTypes.contains(swagNote.noteType)) {
					noteTypes.push(swagNote.noteType);
				}
			}
		}
		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		unspawnNotes.sort(sortByTime);
		generatedMusic = true;

		countNotes();
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);
			
			case 'Play Sound':
				precacheList.set(event.value1, 'sound');
				Paths.sound(event.value1);
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != FunkinLua.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + EnginePreferences.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
	{
		var strumLineX:Float = EnginePreferences.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = EnginePreferences.data.downScroll ? (FlxG.height - 150) : 50;
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!EnginePreferences.data.opponentStrums) targetAlpha = 0;
				else if(EnginePreferences.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = EnginePreferences.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (player == 1)
				playerStrums.add(babyArrow);
			else
			{
				if(EnginePreferences.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) { //Up and Right
						babyArrow.x += FlxG.width / 2 + 25;
					}
				}
				opponentStrums.add(babyArrow);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();

			if(EnginePreferences.data.noteIntro)
				spinnyNotes(babyArrow);
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}

			if (startTimer != null && !startTimer.finished) startTimer.active = false;
			if (finishTimer != null && !finishTimer.finished) finishTimer.active = false;
			if (songSpeedTween != null) songSpeedTween.active = false;

			var chars:Array<Character> = [boyfriend, gf, dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = false;

			#if LUA_ALLOWED
			for (tween in modchartTweens) tween.active = false;
			for (timer in modchartTimers) timer.active = false;
			#end
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong)
			{
				resyncVocals();
			}

			if (startTimer != null && !startTimer.finished) startTimer.active = true;
			if (finishTimer != null && !finishTimer.finished) finishTimer.active = true;
			if (songSpeedTween != null) songSpeedTween.active = true;

			var chars:Array<Character> = [boyfriend, gf, dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = true;

			#if LUA_ALLOWED
			for (tween in modchartTweens) tween.active = true;
			for (timer in modchartTimers) timer.active = true;
			#end

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
		}

		super.closeSubState();
	}

	override public function onFocus():Void
	{
		if (health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if desktop
		if (health > 0 && !paused) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	function resetRPC(?cond:Bool = false)
	{
		#if desktop
		if (cond)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - EnginePreferences.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.play();
		FlxG.sound.music.pitch = playbackRate;
		Conductor.songPosition = FlxG.sound.music.time;
		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = Conductor.songPosition;
			vocals.pitch = playbackRate;
		}

		if (Conductor.songPosition <= opponentVocals.length)
		{
			opponentVocals.time = Conductor.songPosition;
			opponentVocals.pitch = playbackRate;
		}
		vocals.play();
		opponentVocals.play();
	}

	public function spinnyNotes(spriteName) {

		FlxTween.angle(spriteName, 0, 360, 1.3, {type: FlxTween.ONESHOT, ease: FlxEase.sineInOut, startDelay: 0, loopDelay: 0});

		if(!EnginePreferences.data.middleScroll)
		{
			for(i in 0...strumLineNotes.length)
			{
			strumLineNotes.members[i].x = - 300;		
			if (i < 4)
				FlxTween.tween(spriteName, {x: 40 + (120 * i)}, 1.3, {ease: FlxEase.sineInOut, startDelay: 0.5 + (0.2 * i)});
			else
				FlxTween.tween(spriteName, {x: 300 + (120 * i)}, 1.3, {ease: FlxEase.sineInOut, startDelay: 0.5 + (0.2 * i)});
			}
		}
		else
		{
			for(i in 0...strumLineNotes.length)
			{
			strumLineNotes.members[i].x = -1200;
				if(i == 0 || i == 1)
				FlxTween.tween(spriteName, {x: 40 + (120 * i)}, 1.3, {ease: FlxEase.sineInOut, startDelay: 0.5 + (0.2 * i)});

				if(i == 2 || i == 3)
				FlxTween.tween(spriteName, {x: 770 + (120 * i)}, 1.3, {ease: FlxEase.sineInOut, startDelay: 0.5 + (0.2 * i)});

				if(i > 3)
				FlxTween.tween(spriteName, {x: -70 + (120 * i)}, 1.3, {ease: FlxEase.sineInOut, startDelay: 0.5 + (0.2 * i)});

			}
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;

	override public function update(elapsed:Float)
	{
		/*if (FlxG.keys.justPressed.NINE)
		{
			iconP1.swapOldIcon();
		}*/
		callOnScripts('onUpdate', [elapsed]);

		FlxG.camera.followLerp = 0;
		if(!inCutscene && !paused) {
			FlxG.camera.followLerp = FlxMath.bound(elapsed * 2.4 * cameraSpeed * playbackRate / (FlxG.updateFramerate / 60), 0, 1);
			if(!startingSong && !endingSong && boyfriend.animation.curAnim != null && boyfriend.animation.curAnim.name.startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}

		super.update(elapsed);

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		updateIconsAnim(elapsed);
		composer = SONG.composer;

		if(EnginePreferences.data.hud != 'Vanila')
		{
			if(botplayTxt != null && botplayTxt.visible) {
				botplaySine += 180 * elapsed;
				botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
			}
		}

		instAmplitude = (FlxG.sound.music.exists) ? updateAmplitude(FlxG.sound.music) : 0;
		vocalAmplitude = (vocals.exists) ? updateAmplitude(vocals) : 0;
		vocalOpponentAmplitude = (opponentVocals.exists) ? updateAmplitude(opponentVocals) : 0;
		curAmplitude = (instAmplitude + vocalAmplitude + vocalOpponentAmplitude) / 3;

		updateSText();

		lerpScore = FlxMath.lerp(lerpScore, songScore, 0.085);
		lerpRating = FlxMath.lerp(lerpRating, ratingPercent, 0.085);

		var mult:Float = FlxMath.lerp(smoothHealth, health, ((health / smoothHealth) * (elapsed * 8)) * playbackRate);
		smoothHealth = mult;

		if (controls.PAUSE #if android || FlxG.android.justReleased.BACK #end && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != FunkinLua.Function_Stop) {
				openPauseMenu();
			}
		}

		var frames = notesHitArray.length - 1;
		while(frames >= 0)
		{
			var npsHitValue:Date = notesHitArray[frames];

			if (npsHitValue != null && npsHitValue.getTime() + 1000 < Date.now().getTime())
				notesHitArray.remove(npsHitValue);
			else
				frames--;
		}
		nps = notesHitArray.length;

		if (nps > maxNps)
			maxNps = nps;

		if (controls.justPressed('debug_1') && !endingSong && !inCutscene)
			openChartEditor();

		switch(EnginePreferences.data.iconBop)
		{
			case 'Kade':
				var mult:Float = FlxMath.lerp(1, iconP1.scale.x, 0.5 * playbackRate);
				iconP1.scale.set(mult, mult);
				var mult:Float = FlxMath.lerp(1, iconP2.scale.x, 0.5 * playbackRate);
				iconP2.scale.set(mult, mult);
			case 'Psych':
				var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * 9 * playbackRate));
				iconP1.scale.set(mult, mult);
				iconP1.updateHitbox();
				var mult:Float = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * 9 * playbackRate));
				iconP2.scale.set(mult, mult);
				iconP2.updateHitbox();
			case 'Alt':
				var mult:Float = FlxMath.lerp(1, iconP1.scale.x, 0.2 * playbackRate);
				iconP1.scale.set(mult, mult);
				var mult:Float = FlxMath.lerp(1, iconP2.scale.x, 0.2 * playbackRate);
				iconP2.scale.set(mult, mult);
				iconP1.updateHitbox();
				iconP2.updateHitbox();
			case 'Note Hit':
				iconP1.scale.set(1, 1);
				iconP2.scale.set(1, 1);
		}

		var iconOffset:Int = 26;
		if (health > 2) health = 2;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
		//iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0;
		//iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0;

		if (controls.justPressed('debug_2') && !endingSong && !inCutscene)
			openCharacterEditor();
		
		if (startedCountdown && !paused)
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			if(EnginePreferences.data.hud != 'Vanila')
				timeTxt.text = timeStr;		

			var curTime:Float = Math.max(0, Conductor.songPosition - EnginePreferences.data.noteOffset / playbackRate);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(EnginePreferences.data.timeBarType == 'Time Elapsed' || EnginePreferences.data.timeBarType == 'Time Length' || EnginePreferences.data.timeBarType == 'Time Length Percent') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000 / playbackRate);
			if(secondsTotal < 0) secondsTotal = 0;

			switch(EnginePreferences.data.timeBarType)
			{
				case 'Time Elapsed' | 'Time Left':
					timeStr = TimeUtil.formatTime(secondsTotal, false);
				case 'Song Name':
					timeStr = PlayState.SONG.song;
				case 'Time Length':
					timeStr = TimeUtil.formatTime(secondsTotal, false) + ' | ' + TimeUtil.formatTime(songLength / 1000 / playbackRate, false);
				case 'Song Percent':
					timeStr = Std.string(MathUtil.truncatePercent(songPercent, 2)) + '%';
				case 'Time Length Percent':
					timeStr = TimeUtil.formatTime(secondsTotal, false) + ' | ' + TimeUtil.formatTime(songLength / 1000 / playbackRate, false) + ' // ' + Std.string(MathUtil.truncatePercent(songPercent, 2)) + '%';
				case 'Disabled':
					timeStr = "";
			}

			AppUtil.setAppData(AppController.appName, AppController.altEngineVersion + AppController.stage, timeStr);

		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!EnginePreferences.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * playbackRate;
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;

				callOnLuas('onSpawnNote', [notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);

				var index:Int = unspawnNotes.indexOf(dunceNote);
				unspawnNotes.splice(index, 1);
			}
		}

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled) {
					keysCheck();
				} else if(boyfriend.animation.curAnim != null && boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * boyfriend.singDuration && boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.animation.curAnim.name.endsWith('miss')) {
					boyfriend.dance();
					//boyfriend.animation.curAnim.finish();
				}

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						notes.forEachAlive(function(daNote:Note)
						{
							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							if(daNote.mustPress)
							{
								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
									goodNoteHit(daNote);
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
								opponentNoteHit(daNote);

							if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (daNote.mustPress && !cpuControlled &&!daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = false;
								daNote.visible = false;

								daNote.kill();
								notes.remove(daNote, true);
								daNote.destroy();
							}
						});
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}
			}
			checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('cameraX', camFollow.x);
		setOnScripts('cameraY', camFollow.y);
		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);
	}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		// 1 / 1000 chance for Gitaroo Man easter egg
		/*if (FlxG.random.bool(0.1))
		{
			// gitaroo man easter egg
			cancelMusicFadeTween();
			MusicBeatState.switchState(new GitarooPause());
		}
		else {*/
		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));
		//}

		#if desktop
		DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		chartingMode = true;

		#if desktop
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end
		
		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		#if desktop DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != FunkinLua.Function_Stop) {
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;

				opponentVocals.stop();
				vocals.stop();
				FlxG.sound.music.stop();

				persistentUpdate = false;
				persistentDraw = false;
				#if LUA_ALLOWED
				for (tween in modchartTweens) {
					tween.active = true;
				}
				for (timer in modchartTimers) {
					timer.active = true;
				}
				#end
				openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x - boyfriend.positionArray[0], boyfriend.getScreenPosition().y - boyfriend.positionArray[1], camFollow.x, camFollow.y));

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if desktop
				// Game Over doesn't get his own variable because it's only used here
				DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':

				if (FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "Both camera")
				{
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					doCameraBop(flValue1, flValue2);
				}
		
				if (FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "Game camera")
				{
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0;

					//camGame.zoom, camHUD.zoom
					doCameraBop(flValue1, 0);
				}
		
				if (FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "HUD camera")
				{
					if(flValue1 == null) flValue1 = 0;
					if(flValue2 == null) flValue2 = 0.03;

					doCameraBop(0, flValue2);
				}		

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							boyfriend = boyfriendMap.get(value2);
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if(dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							dad = dadMap.get(value2);
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * EnginePreferences.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
				}
			
			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);

			case 'Set Camera Tween':
				var value1split:Array<String> = value1.split(",");
				var value2split:Array<String> = value2.split(",");		

				var easeFunction:Null<Float->Float> = Reflect.field(FlxEase, value2split[0]);
				if (easeFunction == null)
				{
				  trace('Invalid ease function: $easeFunction');
				  return;
				}
				tweening = true;
				tweenCameraZoom(Std.parseFloat(value1split[0]), Std.parseFloat(value1split[1]), easeFunction);
		}
		
		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
	}

	var cameraTwn:FlxTween;
	var cameraZoomTween:FlxTween;

	public function cancelCameraZoomTween()
		{
		  if (cameraZoomTween != null)
		  {
			cameraZoomTween.cancel();
		  }
		}
	  
	public function tweenCameraZoom(?zoom:Float, ?duration:Float, ?ease:Null<Float->Float>):Void
		{
		
		if(tweening)
		{
		  // Cancel the current tween if it's active.
		  cancelCameraZoomTween();
	  
		  // Direct mode: Set zoom directly.
		  // Stage mode: Set zoom as a multiplier of the current stage's default zoom.
		  var targetZoom = zoom * defaultCamZoom;
	  
		  if (duration == 0)
		  {
			// Instant zoom. No tween needed.
			FlxG.camera.zoom = targetZoom;
		  }
		  else
		  {
			// Zoom tween! Caching it so we can cancel/pause it later if needed.
			cameraZoomTween = FlxTween.tween(FlxG.camera, {zoom: targetZoom}, duration, {ease: ease, onComplete: function(twn:FlxTween){
			tweening = false;
			}
			});
		  }
		}
	}

	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function updateIconsAnim(elapsed:Float)
	{
		switch (iconP1.animation.frames)
		{
		case 3:
		if (healthBar.percent < 20)
			iconP1.animation.curAnim.curFrame = 1;
		else if (healthBar.percent > 80 && EnginePreferences.data.winIcon)
			iconP1.animation.curAnim.curFrame = 2;
		else
			iconP1.animation.curAnim.curFrame = 0;

		case 2:
		if (healthBar.percent < 20)
			iconP1.animation.curAnim.curFrame = 1;
		else
			iconP1.animation.curAnim.curFrame = 0;

		case 1:
			iconP1.animation.curAnim.curFrame = 0;
		}

		switch (iconP2.animation.frames)
		{
			case 3:
				if (healthBar.percent > 80)
					iconP2.animation.curAnim.curFrame = 1;
				else if (healthBar.percent < 20 && EnginePreferences.data.winIcon)
					iconP2.animation.curAnim.curFrame = 2;
				else 
					iconP2.animation.curAnim.curFrame = 0;
			case 2:
				if (healthBar.percent > 80)
					iconP2.animation.curAnim.curFrame = 1;
				else 
					iconP2.animation.curAnim.curFrame = 0;
			case 1:
					iconP2.animation.curAnim.curFrame = 0;
		}
	}
	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();
		
		if(EnginePreferences.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(EnginePreferences.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		finishedSong = true;
	    #if android
		MusicBeatState.androidc.visible = false;
	 	#end
		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			});
			for (daNote in unspawnNotes) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		if(EnginePreferences.data.hud != 'Vanila')
		{
			timeBar.visible = false;
			timeTxt.visible = false;
		}
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		if(achievementObj != null)
			return false;
		else
		{
			var noMissWeek:String = WeekData.getWeekFileName() + '_nomiss';
			var achieve:String = checkForAchievement([noMissWeek, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
			if(achieve != null) {
				startAchievement(achieve);
				return false;
			}
		}
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != FunkinLua.Function_Stop && !transitioning)
		{
			#if !switch
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent);
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if desktop DiscordClient.resetClientID(); #end

					cancelMusicFadeTween();
					
					if(EnginePreferences.data.results)
					{
						canPause = false;
						openSubState(new substates.ResultsScreenSubState([sicks, goods, bads, shits], campaignScore, campaignMisses, MathUtil.truncateFloat(ratingPercent * 100, 2)));
					}
					else
					{
						MusicBeatState.switchState(new states.StoryMenuState());
					}

					// if ()
					if(!EnginePreferences.getGameplaySetting('practice') && !EnginePreferences.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					cancelMusicFadeTween();
					MusicBeatState.switchState(new LoadingScreenState());
					LoadingScreenState.inPlayState = true;
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if desktop DiscordClient.resetClientID(); #end

				cancelMusicFadeTween();

				if(EnginePreferences.data.results)
				{
					canPause = false;
					openSubState(new substates.ResultsScreenSubState([sicks, goods, bads, shits], songScore, songMisses, MathUtil.truncateFloat(ratingPercent * 100, 2)));
				}
				else
				{
					MusicBeatState.switchState(new states.FreeplayState());
				}
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

	#if ACHIEVEMENTS_ALLOWED
	var achievementObj:AchievementPopup = null;
	function startAchievement(achieve:String) {
		achievementObj = new AchievementPopup(achieve, camOther);
		achievementObj.onFinish = achievementEnd;
		add(achievementObj);
		trace('Giving achievement ' + achieve);
	}
	function achievementEnd():Void
	{
		achievementObj = null;
		if(endingSong && !inCutscene) {
			endSong();
		}
	}
	#end

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;

			daNote.kill();
			notes.remove(daNote, true);
			daNote.destroy();
		}
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// stores the last judgement object
	var lastRating:FlxSprite;
	// stores the last combo sprite object
	var lastCombo:FlxSprite;
	// stores the last combo score objects in an array
	var lastScore:Array<FlxSprite> = [];

	private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ratingsData)
			Paths.image(uiPrefix + rating.image + uiSuffix);
		for (i in 0...10)
			Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	private function popUpScore(note:Note = null):Void
	{
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition + EnginePreferences.data.ratingOffset);
		vocals.volume = 1;
		opponentVocals.volume = 1;

		var placement:Float =  FlxG.width * 0.35;
		var rating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
		ratingHealth = daRating.hitHealth;

		switch(daRating.image)
		{
			case 'sick':
				hitVal = 1; 
			case 'good':
				hitVal = 2; 
			case 'bad':
				hitVal = 3; 
			case 'shit':
				hitVal = 4; 
		}
		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		if(!practiceMode && !cpuControlled) {
			songScore += score;
			if(!note.ratingDisabled)
			{
				songHits++;
				totalPlayed++;
				RecalculateRating(false);
			}
		}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = EnginePreferences.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		if(EnginePreferences.data.popUpRating && !cpuControlled)
		{
		rating.loadGraphic(Paths.image(uiPrefix + daRating.image + uiSuffix));
		rating.cameras = [camHUD];
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * playbackRate * playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		rating.visible = (!EnginePreferences.data.hideHud && showRating);
		rating.x += EnginePreferences.data.comboOffset[0];
		rating.y -= EnginePreferences.data.comboOffset[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
		comboSpr.cameras = [camHUD];
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
		comboSpr.visible = (!EnginePreferences.data.hideHud && showCombo);
		comboSpr.x += EnginePreferences.data.comboOffset[0];
		comboSpr.y -= EnginePreferences.data.comboOffset[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
		comboGroup.add(rating);
		
		if (!EnginePreferences.data.comboStacking && comboGroup.members.length > 0) {
			for (spr in comboGroup) {
				spr.destroy();
				comboGroup.remove(spr);
			}
		}

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var seperatedScore:Array<Int> = [];

		if(combo >= 1000) {
			seperatedScore.push(Math.floor(combo / 1000) % 10);
		}
		seperatedScore.push(Math.floor(combo / 100) % 10);
		seperatedScore.push(Math.floor(combo / 10) % 10);
		seperatedScore.push(combo % 10);

		var daLoop:Int = 0;
		var xThing:Float = 0;

		if (showCombo)
			comboGroup.add(comboSpr);

		if (!EnginePreferences.data.comboStacking)
		{
			if (lastCombo != null) lastCombo.kill();
			lastCombo = comboSpr;
		}
		if (lastScore != null)
		{
			while (lastScore.length > 0)
			{
				lastScore[0].kill();
				lastScore.remove(lastScore[0]);
			}
		}
		for (i in seperatedScore)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + EnginePreferences.data.comboOffset[2];
			numScore.y += 80 - EnginePreferences.data.comboOffset[3];
			
			if (!EnginePreferences.data.comboStacking)
				lastScore.push(numScore);

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.visible = !EnginePreferences.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		comboSpr.x = xThing + 50;
		FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
			startDelay: Conductor.crochet * 0.001 / playbackRate
		});

		FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
			onComplete: function(tween:FlxTween)
			{
				comboSpr.destroy();
				rating.destroy();
			},
			startDelay: Conductor.crochet * 0.002 / playbackRate
		});
	}
}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if (!controls.controllerMode && FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
	}

	private function keyPressed(key:Int)
	{
		if (!cpuControlled && startedCountdown && !paused && key > -1)
		{
			if(notes.length > 0 && !boyfriend.stunned && generatedMusic && !endingSong)
			{
				//more accurate hit time for the ratings?
				var lastTime:Float = Conductor.songPosition;
				if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time;

				var canMiss:Bool = !EnginePreferences.data.ghostTapping;

				// heavily based on my own code LOL if it aint broke dont fix it
				var pressNotes:Array<Note> = [];
				var notesStopped:Bool = false;
				var sortedNotesList:Array<Note> = [];
				notes.forEachAlive(function(daNote:Note)
				{
					if (strumsBlocked[daNote.noteData] != true && daNote.canBeHit && daNote.mustPress &&
						!daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
					{
						if(daNote.noteData == key) sortedNotesList.push(daNote);
						canMiss = true;
					}
				});
				sortedNotesList.sort(sortHitNotes);

				if (sortedNotesList.length > 0) {
					for (epicNote in sortedNotesList)
					{
						for (doubleNote in pressNotes) {
							if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1) {
								doubleNote.kill();
								notes.remove(doubleNote, true);
								doubleNote.destroy();
							} else
								notesStopped = true;
						}

						// eee jack detection before was not super good
						if (!notesStopped) {
							goodNoteHit(epicNote);
							pressNotes.push(epicNote);
						}

					}
				}
				else {
					callOnScripts('onGhostTap', [key]);
					if (canMiss && !boyfriend.stunned) noteMissPress(key);
				}

				// I dunno what you need this for but here you go
				//									- Shubs

				// Shubs, this is for the "Just the Two of Us" achievement lol
				//									- Shadow Mario
				if(!keysPressed.contains(key)) keysPressed.push(key);

				//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
				Conductor.songPosition = lastTime;
			}

			var spr:StrumNote = playerStrums.members[key];
			if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
			{
				spr.playAnim('pressed');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyPress', [key]);
		}
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		//trace('Pressed: ' + eventKey);

		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(!cpuControlled && startedCountdown && !paused)
		{
			var spr:StrumNote = playerStrums.members[key];
			if(spr != null)
			{
				spr.playAnim('static');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyRelease', [key]);
		}
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in keysArray)
		{
			holdArray.push(controls.pressed(key));
			pressArray.push(controls.justPressed(key));
			releaseArray.push(controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !boyfriend.stunned && generatedMusic)
		{
			// rewritten inputs???
			if(notes.length > 0)
			{
				notes.forEachAlive(function(daNote:Note)
				{
					// hold note functions
					if (strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && holdArray[daNote.noteData] && daNote.canBeHit
					&& daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit) {
						goodNoteHit(daNote);
					}
				});
			}

			if (holdArray.contains(true) && !endingSong) {
				#if ACHIEVEMENTS_ALLOWED
				var achieve:String = checkForAchievement(['oversinging']);
				if (achieve != null) {
					startAchievement(achieve);
				}
				#end
			}
			else if (boyfriend.animation.curAnim != null && boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * boyfriend.singDuration && boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.animation.curAnim.name.endsWith('miss'))
			{
				boyfriend.dance();
				//boyfriend.animation.curAnim.finish();
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1) {
				note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		});
		
		noteMissCommon(daNote.noteData, daNote);
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(EnginePreferences.data.ghostTapping) return; //fuck it

		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;
		health -= subtract * healthLoss;

		if(instakillOnMiss)
		{
			vocals.stop();
			opponentVocals.stop();

			doDeathCheck(true);
		}
		combo = 0;

		if(!practiceMode) songScore -= 10;
		if(!endingSong) songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		// play character anims
		var char:Character = boyfriend;
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;
		
		if(char != null && char.hasMissAnimations)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);
			
			if(char != gf && combo > 5 && gf != null && gf.animOffsets.exists('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
		opponentVocals.volume = 1;

	}

	function moveIcon(?isDad:Bool = false)
		{
			if(isDad == false)
			{
				if(iconZoomTween != null) {
					iconZoomTween.cancel();
				}
				iconP1.y = healthBar.y - 85;
				iconZoomTween = FlxTween.tween(iconP1, {y: healthBar.y - 90}, 0.1, {
					ease: FlxEase.cubeInOut,
					onComplete: function(twn:FlxTween)
					{
						iconZoomTween = FlxTween.tween(iconP1, {y: healthBar.y - 75}, (Conductor.crochet / 1000), {
							ease: FlxEase.cubeInOut,
							onComplete: function(twn:FlxTween)
							{
								iconZoomTween = null;
							}
						});
					}
				});
			}
			else
			{
				if(iconDadZoomTween != null) {
					iconDadZoomTween.cancel();
				}
				iconP2.y = healthBar.y - 85;
				iconDadZoomTween = FlxTween.tween(iconP2, {y: healthBar.y - 90}, 0.1, {
					ease: FlxEase.cubeInOut,
					onComplete: function(twn:FlxTween)
					{
						iconDadZoomTween = FlxTween.tween(iconP2, {y: healthBar.y - 75}, (Conductor.crochet / 1000), {
							ease: FlxEase.cubeInOut,
							onComplete: function(twn:FlxTween)
							{
								iconDadZoomTween = null;
							}
						});
					}
				});
			}
		}

	function opponentNoteHit(note:Note):Void
	{
		if (Paths.formatToSongPath(SONG.song) != 'tutorial')
			camZooming = true;

		if(note.noteType == 'Hey!' && dad.animOffsets.exists('hey')) {
			dad.playAnim('hey', true);
			dad.specialAnim = true;
			dad.heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (SONG.notes[curSection] != null)
			{
				if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
					altAnim = '-alt';
				}
			}

			var char:Character = dad;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) {
				char = gf;
			}

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if (SONG.needsVoices)
		{
			vocals.volume = 1;
			opponentVocals.volume = 1;

		}

		if(!note.isSustainNote && EnginePreferences.data.iconBop == 'Note Hit')
			moveIcon(true);

		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;

		var result:Dynamic = callOnLuas('opponentNoteHit', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('opponentNoteHit', [note]);

		if (!note.isSustainNote)
		{
			note.kill();
			notes.remove(note, true);
			note.destroy();
		}
	}

	function goodNoteHit(note:Note):Void
	{
		if (!note.wasGoodHit)
		{
			if(cpuControlled && (note.ignoreNote || note.hitCausesMiss)) return;

			note.wasGoodHit = true;
			if (EnginePreferences.data.hitsoundVolume > 0 && !note.hitsoundDisabled)
				FlxG.sound.play(Paths.sound(note.hitsound), EnginePreferences.data.hitsoundVolume);

			if(note.hitCausesMiss) {
				noteMiss(note);
				if(!note.noteSplashData.disabled && !note.isSustainNote)
					spawnNoteSplashOnNote(note);

				if(!note.isSustainNote && EnginePreferences.data.iconBop == 'Note Hit')
					moveIcon(false);

				if(!note.noMissAnimation)
				{
					switch(note.noteType) {
						case 'Hurt Note': //Hurt note
							if(boyfriend.animation.getByName('hurt') != null) {
								boyfriend.playAnim('hurt', true);
								boyfriend.specialAnim = true;
							}
					}
				}

				if (!note.isSustainNote)
				{
					note.kill();
					notes.remove(note, true);
					note.destroy();
				}
				return;
			}

			if (!note.isSustainNote)
			{
				combo++;
				if(combo > 9999) combo = 9999;
				hitVal = 0; 
				popUpScore(note);
				notesHitArray.push(Date.now());
			}
			health += note.hitHealth * healthGain;

			if(!note.noAnimation) {
				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))];

				var char:Character = boyfriend;
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}
				
				if(char != null)
				{
					char.playAnim(animToPlay + note.animSuffix, true);
					char.holdTimer = 0;
					
					if(note.noteType == 'Hey!') {
						if(char.animOffsets.exists(animCheck)) {
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
			}

			if(!cpuControlled)
			{
				var spr = playerStrums.members[note.noteData];
				if(spr != null) spr.playAnim('confirm', true);
			}
			else strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			vocals.volume = 1;
			opponentVocals.volume = 1;

			var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
			var leData:Int = Math.round(Math.abs(note.noteData));
			var leType:String = note.noteType;
			
			var result:Dynamic = callOnLuas('goodNoteHit', [notes.members.indexOf(note), leData, leType, isSus]);
			if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('goodNoteHit', [note]);

			if (!note.isSustainNote)
			{
				note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		}
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		#if LUA_ALLOWED
		for (i in 0...luaArray.length) {
			var lua:FunkinLua = luaArray[0];
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		FlxAnimationController.globalSpeed = 1;
		FlxG.sound.music.pitch = 1;
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		instance = null;
		super.destroy();
	}

	public function cancelMusicFadeTween() {
		if(FlxG.sound.music.fadeTween != null) {
			FlxG.sound.music.fadeTween.cancel();
		}
		FlxG.sound.music.fadeTween = null;
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (SONG.needsVoices && FlxG.sound.music.time >= -EnginePreferences.data.noteOffset)
		{
			var timeSub:Float = Conductor.songPosition - Conductor.offset;
			var syncTime:Float = 20 * playbackRate;
			if (Math.abs(FlxG.sound.music.time - timeSub) > syncTime ||
			(vocals.length > 0 && Math.abs(vocals.time - timeSub) > syncTime) ||
			(opponentVocals.length > 0 && Math.abs(opponentVocals.time - timeSub) > syncTime))
			{
				resyncVocals();
			}
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, EnginePreferences.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		switch(EnginePreferences.data.iconBop)
		{
			case 'Alt':
			iconP1.scale.set(1.45, 1.45);
			iconP2.scale.set(1.45, 1.45);
			case 'Psych':
			iconP1.scale.set(1.2, 1.2);
			iconP2.scale.set(1.2, 1.2);
			case 'Kade':
			iconP1.scale.set(1.15, 1.15);
			iconP2.scale.set(1.15, 1.15);
		}

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		if (gf != null && curBeat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && gf.animation.curAnim != null && !gf.animation.curAnim.name.startsWith("sing") && !gf.stunned)
			gf.dance();
		if (curBeat % boyfriend.danceEveryNumBeats == 0 && boyfriend.animation.curAnim != null && !boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (curBeat % dad.danceEveryNumBeats == 0 && dad.animation.curAnim != null && !dad.animation.curAnim.name.startsWith('sing') && !dad.stunned)
			dad.dance();

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	override function sectionHit()
	{
		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();
			
			if (camZooming && FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "Both camera")
			{
				doCameraBop(0.015 * camZoomingMult, 0.03 * camZoomingMult);
			}

			if (camZooming && FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "Game camera")
			{
				doCameraBop(0.015 * camZoomingMult, 0 * camZoomingMult);
			}

			if (camZooming && FlxG.camera.zoom < 1.35 && EnginePreferences.data.camZooms && EnginePreferences.data.beatMode == "HUD camera")
			{
				doCameraBop(0 * camZoomingMult, 0.03 * camZoomingMult);
			}

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();
		
		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getPreloadPath(luaFile);
		
		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;
	
			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end
	
	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
{
    #if MODS_ALLOWED
    var scriptToLoad:String = Paths.modFolders(scriptFile);
    if(!FileSystem.exists(scriptToLoad))
        scriptToLoad = Paths.getPreloadPath(scriptFile);

    if(FileSystem.exists(scriptToLoad))
    #elseif sys
    var scriptToLoad:String = Paths.getPreloadPath(scriptFile);
    if(OpenFlAssets.exists(scriptToLoad))
    #end
    {
        if (SScript.global.exists(scriptToLoad)) return false;

        initHScript(scriptToLoad);
        return true;
    }
    return false;
}

	public function initHScript(file:String)
	{
		try
		{
			var newScript:HScript = new HScript(null, file);
			@:privateAccess
			if(newScript.parsingExceptions != null && newScript.parsingExceptions.length > 0)
			{
				@:privateAccess
				for (e in newScript.parsingExceptions)
					if(e != null)
						addTextToDebug('ERROR ON LOADING ($file): ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
						if (e != null)
							addTextToDebug('ERROR ($file: onCreate) - ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);

					newScript.destroy();
					hscriptArray.remove(newScript);
					trace('failed to initialize sscript interp!!! ($file)');
				}
				else trace('initialized sscript interp successfully: $file');
			}
			
		}
		catch(e)
		{
			addTextToDebug('ERROR ($file) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [psychlua.FunkinLua.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = FunkinLua.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [FunkinLua.Function_Continue];

		var len:Int = luaArray.length;
		var i:Int = 0;
		while(i < len)
		{
			var script:FunkinLua = luaArray[i];
			if(exclusions.contains(script.scriptName))
			{
				i++;
				continue;
			}

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}
			
			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(!script.closed) i++;
			else len--;
		}
		#end
		return returnVal;
	}
	
	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(psychlua.FunkinLua.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len)
		{
			var script:HScript = hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try
			{
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
						FunkinLua.luaTrace('ERROR (${script.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), true, false, FlxColor.RED);
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == FunkinLua.Function_StopHScript || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}
					
					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim((EnginePreferences.data.lightStrums) ? 'confirm' : 'static', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var lerpRating:Float = 0;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != FunkinLua.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce -Ghost
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
	}

	public dynamic function fullComboFunction()
		{
	
			sicks = ratingsData[0].hits;
			goods = ratingsData[1].hits;
			bads = ratingsData[2].hits;
			shits = ratingsData[3].hits;
	
			hitPercent = (songHits / totalNotes);
			sickPercent = (sicks / songHits);
			goodPercent = (goods / songHits);
			badPercent = (bads / songHits);
			shitPercent = (shits / songHits);
			
			ratingFC = "";
			if(songMisses == 0)
			{
				if (bads > 0 || shits > 0) ratingFC = 'FC';
				else if (goods > 0) ratingFC = 'GFC';
				else if (sicks > 0) ratingFC = 'SFC';
			}
			else {
				if (songMisses < 10) ratingFC = 'SDCB';
				else ratingFC = 'Clear';
			}
		}


	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null):String
	{
		if(chartingMode) return null;

		var usedPractice:Bool = (EnginePreferences.getGameplaySetting('practice') || EnginePreferences.getGameplaySetting('botplay'));
		for (i in 0...achievesToCheck.length) {
			var achievementName:String = achievesToCheck[i];
			if(!Achievements.isAchievementUnlocked(achievementName) && !cpuControlled && Achievements.getAchievementIndex(achievementName) > -1) {
				var unlock:Bool = false;
				if (achievementName == WeekData.getWeekFileName() + '_nomiss') // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
				{
					if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
						&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
						unlock = true;
				}
				else
				{
					switch(achievementName)
					{
						case 'ur_bad':
							unlock = (ratingPercent < 0.2 && !practiceMode);

						case 'ur_good':
							unlock = (ratingPercent >= 1 && !usedPractice);

						case 'roadkill_enthusiast':
							unlock = (Achievements.henchmenDeath >= 50);

						case 'oversinging':
							unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

						case 'hype':
							unlock = (!boyfriendIdled && !usedPractice);

						case 'two_keys':
							unlock = (!usedPractice && keysPressed.length <= 2);

						case 'toastie':
							unlock = (/*EnginePreferences.data.framerate <= 60 &&*/ !EnginePreferences.data.shaders && EnginePreferences.data.lowQuality && !EnginePreferences.data.antialiasing);

						case 'debugger':
							unlock = (Paths.formatToSongPath(SONG.song) == 'test' && !usedPractice);
					}
				}

				if(unlock) {
					Achievements.unlockAchievement(achievementName);
					return achievementName;
				}
			}
		}
		return null;
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!EnginePreferences.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String)
	{
		if(!EnginePreferences.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));
		
		for (folder in foldersToCheck)
		{
			if(FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else frag = null;

				if(FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}
	#end

	public function reloadTimeBarColors() {
		switch(EnginePreferences.data.hud)
		{
			case "Psych Engine":
			timeBar.leftBar.color = FlxColor.WHITE;
			timeBar.rightBar.color = FlxColor.BLACK;
			case "Kade Engine":
			timeBar.leftBar.color = FlxColor.LIME;
			timeBar.rightBar.color = FlxColor.GRAY;
		}
	}

	#if (lime_cffi && !macro)
	function updateAmplitude(sound:FlxSound) {
		var snd = sound;
		var curAmplitude:Float = 0;		

		var midx = 100 / 2;

		var currentTime = snd.time;
		
		var buffer = snd._sound.__buffer;
		var bytes = buffer.data.buffer;
		
		var length = bytes.length - 1;
		var khz = (buffer.sampleRate / 1000);
		var channels = buffer.channels;
		var stereo = channels > 1;
		var src = buffer.src;
		var bitsPerSample = buffer.bitsPerSample;
		
		var index = Math.floor(currentTime * khz);
		var samples = 720;//Math.floor((currentTime + (((60 / Conductor.bpm) * 1000 / 4) * 16)) * khz - index);
		var samplesPerRow = samples / 720;

		var lmin:Float = 0;
		var lmax:Float = 0;
		
		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows = 0;
		var render = 0;
		var prevRows = 0;
		
		var byte = 0;
		
		while (index < length) {
			if (index >= 0) {
				byte = bytes.getUInt16(index * channels * 2);

				if (byte > 65535 / 2) byte -= 65535;

				var sample = (byte / 65535);

				if (sample > 0) {
					if (sample > lmax) lmax = sample;
				} else if (sample < 0) {
					if (sample < lmin) lmin = sample;
				}

				if (stereo) {
					 byte = bytes.getUInt16((index * channels * 2) + 2);

					if (byte > 65535 / 2) byte -= 65535;

					var sample = (byte / 65535);

					if (sample > 0) {
						if (sample > rmax) rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin) rmin = sample;
					}
				}
			}
			
			if (rows - prevRows >= samplesPerRow) {
				prevRows = rows + ((rows - prevRows) - 1);
				
				curAmplitude = (((rmax - rmin) * midx * 2) / 45);

				lmin = lmax = rmin = rmax = 0;
				render++;
			}
			
			index++;
			rows++;
			if (render > (640 - 50 - 1)) break;

		}
		return curAmplitude;
	}
#end

		function countNotes()
		{
			for(i in 0...unspawnNotes.length)
			{
				if(unspawnNotes[i].mustPress && !unspawnNotes[i].isSustainNote)
				{
					totalNotes++;
				}
			}
		}
}
