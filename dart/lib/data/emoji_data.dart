import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:characters/characters.dart';
import 'package:uniclient/utils/debug.dart';

const List<EmojiEntry> kEmojiSuggestions = [
  EmojiEntry('#️⃣', ['hash']),
  EmojiEntry('0️⃣', ['zero']),
  EmojiEntry('1️⃣', ['one']),
  EmojiEntry('2️⃣', ['two']),
  EmojiEntry('3️⃣', ['three']),
  EmojiEntry('4️⃣', ['four']),
  EmojiEntry('5️⃣', ['five']),
  EmojiEntry('6️⃣', ['six']),
  EmojiEntry('7️⃣', ['seven']),
  EmojiEntry('8️⃣', ['eight']),
  EmojiEntry('9️⃣', ['nine']),
  EmojiEntry('©️', ['copyright']),
  EmojiEntry('®️', ['registered']),
  EmojiEntry('‼️', ['bangbang']),
  EmojiEntry('⁉️', ['interrobang']),
  EmojiEntry('™️', ['tm']),
  EmojiEntry('ℹ️', ['information_source']),
  EmojiEntry('↔️', ['left_right_arrow']),
  EmojiEntry('↕️', ['arrow_up_down']),
  EmojiEntry('↖️', ['arrow_upper_left']),
  EmojiEntry('🥉', ['third_place', 'third_place_medal']),
  EmojiEntry('↗️', ['arrow_upper_right']),
  EmojiEntry('↘️', ['arrow_lower_right']),
  EmojiEntry('↙️', ['arrow_lower_left']),
  EmojiEntry('🥈', ['second_place', 'second_place_medal']),
  EmojiEntry('↩️', ['leftwards_arrow_with_hook']),
  EmojiEntry('↪️', ['arrow_right_hook']),
  EmojiEntry('⌚', ['watch']),
  EmojiEntry('⌛', ['hourglass']),
  EmojiEntry('⏩', ['fast_forward']),
  EmojiEntry('⏪', ['rewind']),
  EmojiEntry('⏫', ['arrow_double_up']),
  EmojiEntry('⏬', ['arrow_double_down']),
  EmojiEntry('⏰', ['alarm_clock']),
  EmojiEntry('⏳', ['hourglass_flowing_sand']),
  EmojiEntry('Ⓜ️', ['m']),
  EmojiEntry('▪️', ['black_small_square']),
  EmojiEntry('▫️', ['white_small_square']),
  EmojiEntry('▶️', ['arrow_forward']),
  EmojiEntry('◀️', ['arrow_backward']),
  EmojiEntry('◻️', ['white_medium_square']),
  EmojiEntry('◼️', ['black_medium_square']),
  EmojiEntry('◽', ['white_medium_small_square']),
  EmojiEntry('◾', ['black_medium_small_square']),
  EmojiEntry('☀️', ['sunny']),
  EmojiEntry('☁️', ['cloud']),
  EmojiEntry('☎️', ['telephone']),
  EmojiEntry('☑️', ['ballot_box_with_check']),
  EmojiEntry('☔', ['umbrella']),
  EmojiEntry('☕', ['coffee']),
  EmojiEntry('☝️', ['point_up']),
  EmojiEntry('☺️', ['relaxed']),
  EmojiEntry('♈', ['aries']),
  EmojiEntry('🥇', ['first_place', 'first_place_medal']),
  EmojiEntry('♉', ['taurus']),
  EmojiEntry('🤺', ['person_fencing', 'fencer', 'fencing']),
  EmojiEntry('♊', ['gemini']),
  EmojiEntry('♋', ['cancer']),
  EmojiEntry('🥅', ['goal', 'goal_net']),
  EmojiEntry('♌', ['leo']),
  EmojiEntry('*️', ['asterisk_symbol']),
  EmojiEntry('♍', ['virgo']),
  EmojiEntry('🤾', ['person_playing_handball', 'handball']),
  EmojiEntry('♎', ['libra']),
  EmojiEntry('🇿', ['regional_indicator_z']),
  EmojiEntry('🤽', ['person_playing_water_polo', 'water_polo']),
  EmojiEntry('♏', ['scorpius']),
  EmojiEntry('♐', ['sagittarius']),
  EmojiEntry('🥋', ['martial_arts_uniform', 'karate_uniform']),
  EmojiEntry('♑', ['capricorn']),
  EmojiEntry('🥊', ['boxing_glove', 'boxing_gloves']),
  EmojiEntry('♒', ['aquarius']),
  EmojiEntry('🤼', ['people_wrestling', 'wrestlers', 'wrestling']),
  EmojiEntry('♓', ['pisces']),
  EmojiEntry('♠️', ['spades']),
  EmojiEntry('♣️', ['clubs']),
  EmojiEntry('♥️', ['hearts']),
  EmojiEntry('♦️', ['diamonds']),
  EmojiEntry('♨️', ['hotsprings']),
  EmojiEntry('♻️', ['recycle']),
  EmojiEntry('🤹', ['person_juggling', 'juggling', 'juggler']),
  EmojiEntry('♿', ['wheelchair']),
  EmojiEntry('⚓', ['anchor']),
  EmojiEntry('⚠️', ['warning']),
  EmojiEntry('⚡', ['zap']),
  EmojiEntry('⚪', ['white_circle']),
  EmojiEntry('⚫', ['black_circle']),
  EmojiEntry('⚽', ['soccer']),
  EmojiEntry('⚾', ['baseball']),
  EmojiEntry('⛄', ['snowman']),
  EmojiEntry('⛅', ['partly_sunny']),
  EmojiEntry('⛎', ['ophiuchus']),
  EmojiEntry('🤸', ['person_doing_cartwheel', 'cartwheel']),
  EmojiEntry('⛔', ['no_entry']),
  EmojiEntry('⛪', ['church']),
  EmojiEntry('⛲', ['fountain']),
  EmojiEntry('🛶', ['canoe', 'kayak']),
  EmojiEntry('⛳', ['golf']),
  EmojiEntry('⛵', ['sailboat']),
  EmojiEntry('⛺', ['tent']),
  EmojiEntry('⛽', ['fuelpump']),
  EmojiEntry('✂️', ['scissors']),
  EmojiEntry('✅', ['white_check_mark']),
  EmojiEntry('✈️', ['airplane']),
  EmojiEntry('✉️', ['envelope']),
  EmojiEntry('✊', ['fist']),
  EmojiEntry('✋', ['raised_hand']),
  EmojiEntry('✌️', ['v']),
  EmojiEntry('✏️', ['pencil2']),
  EmojiEntry('✒️', ['black_nib']),
  EmojiEntry('✔️', ['heavy_check_mark']),
  EmojiEntry('✖️', ['heavy_multiplication_x']),
  EmojiEntry('✨', ['sparkles']),
  EmojiEntry('✳️', ['eight_spoked_asterisk']),
  EmojiEntry('✴️', ['eight_pointed_black_star']),
  EmojiEntry('❄️', ['snowflake']),
  EmojiEntry('❇️', ['sparkle']),
  EmojiEntry('❌', ['x']),
  EmojiEntry('❎', ['negative_squared_cross_mark']),
  EmojiEntry('❓', ['question']),
  EmojiEntry('❔', ['grey_question']),
  EmojiEntry('🛵', ['motor_scooter', 'motorbike']),
  EmojiEntry('❕', ['grey_exclamation']),
  EmojiEntry('❗', ['exclamation']),
  EmojiEntry('❤️', ['heart']),
  EmojiEntry('➕', ['heavy_plus_sign']),
  EmojiEntry('➖', ['heavy_minus_sign']),
  EmojiEntry('➗', ['heavy_division_sign']),
  EmojiEntry('➡️', ['arrow_right']),
  EmojiEntry('➰', ['curly_loop']),
  EmojiEntry('⤴️', ['arrow_heading_up']),
  EmojiEntry('⤵️', ['arrow_heading_down']),
  EmojiEntry('⬅️', ['arrow_left']),
  EmojiEntry('⬆️', ['arrow_up']),
  EmojiEntry('🛴', ['scooter']),
  EmojiEntry('⬇️', ['arrow_down']),
  EmojiEntry('⬛', ['black_large_square']),
  EmojiEntry('⬜', ['white_large_square']),
  EmojiEntry('⭐', ['star']),
  EmojiEntry('⭕', ['o']),
  EmojiEntry('〰️', ['wavy_dash']),
  EmojiEntry('〽️', ['part_alternation_mark']),
  EmojiEntry('㊗️', ['congratulations']),
  EmojiEntry('🛒', ['shopping_cart', 'shopping_trolley']),
  EmojiEntry('㊙️', ['secret']),
  EmojiEntry('🀄', ['mahjong']),
  EmojiEntry('🃏', ['black_joker']),
  EmojiEntry('🅰️', ['a']),
  EmojiEntry('🅱️', ['b']),
  EmojiEntry('🅾️', ['o2']),
  EmojiEntry('🅿️', ['parking']),
  EmojiEntry('🛑', ['octagonal_sign', 'stop_sign']),
  EmojiEntry('🆎', ['ab']),
  EmojiEntry('🆑', ['cl']),
  EmojiEntry('🇾', ['regional_indicator_y']),
  EmojiEntry('🆒', ['cool']),
  EmojiEntry('🆓', ['free']),
  EmojiEntry('🆔', ['id']),
  EmojiEntry('🆕', ['new']),
  EmojiEntry('🆖', ['ng']),
  EmojiEntry('🆗', ['ok']),
  EmojiEntry('🆘', ['sos']),
  EmojiEntry('🥄', ['spoon']),
  EmojiEntry('🆙', ['up']),
  EmojiEntry('🆚', ['vs']),
  EmojiEntry('🇨🇳', ['flag_cn', 'cn']),
  EmojiEntry('🇩🇪', ['flag_de', 'de']),
  EmojiEntry('🇪🇸', ['flag_es', 'es']),
  EmojiEntry('🇫🇷', ['flag_fr', 'fr']),
  EmojiEntry('🇬🇧', ['flag_gb', 'gb']),
  EmojiEntry('🥂', ['champagne_glass', 'clinking_glass']),
  EmojiEntry('🥃', ['tumbler_glass', 'whisky']),
  EmojiEntry('🇮🇹', ['flag_it', 'it']),
  EmojiEntry('🇯🇵', ['flag_jp', 'jp']),
  EmojiEntry('🇰🇷', ['flag_kr', 'kr']),
  EmojiEntry('🇺🇸', ['flag_us', 'us']),
  EmojiEntry('🇷🇺', ['flag_ru', 'ru']),
  EmojiEntry('🈁', ['koko']),
  EmojiEntry('🈂️', ['sa']),
  EmojiEntry('🈚', ['u7121']),
  EmojiEntry('🈯', ['u6307']),
  EmojiEntry('🥙', ['stuffed_flatbread', 'stuffed_pita']),
  EmojiEntry('🈲', ['u7981']),
  EmojiEntry('🈳', ['u7a7a']),
  EmojiEntry('🈴', ['u5408']),
  EmojiEntry('🈵', ['u6e80']),
  EmojiEntry('🈶', ['u6709']),
  EmojiEntry('🥘', ['shallow_pan_of_food', 'paella']),
  EmojiEntry('🈷️', ['u6708']),
  EmojiEntry('🈸', ['u7533']),
  EmojiEntry('🈹', ['u5272']),
  EmojiEntry('🥗', ['salad', 'green_salad']),
  EmojiEntry('🈺', ['u55b6']),
  EmojiEntry('🉐', ['ideograph_advantage']),
  EmojiEntry('🉑', ['accept']),
  EmojiEntry('🌀', ['cyclone']),
  EmojiEntry('🥖', ['french_bread', 'baguette_bread']),
  EmojiEntry('🌁', ['foggy']),
  EmojiEntry('🌂', ['closed_umbrella']),
  EmojiEntry('🌃', ['night_with_stars']),
  EmojiEntry('🌄', ['sunrise_over_mountains']),
  EmojiEntry('🌅', ['sunrise']),
  EmojiEntry('🌆', ['city_dusk']),
  EmojiEntry('🥕', ['carrot']),
  EmojiEntry('🌇', ['city_sunset', 'city_sunrise']),
  EmojiEntry('🌈', ['rainbow']),
  EmojiEntry('🥔', ['potato']),
  EmojiEntry('🌉', ['bridge_at_night']),
  EmojiEntry('🌊', ['ocean']),
  EmojiEntry('🌋', ['volcano']),
  EmojiEntry('🌌', ['milky_way']),
  EmojiEntry('🌏', ['earth_asia']),
  EmojiEntry('🌑', ['new_moon']),
  EmojiEntry('🥓', ['bacon']),
  EmojiEntry('🌓', ['first_quarter_moon']),
  EmojiEntry('🌔', ['waxing_gibbous_moon']),
  EmojiEntry('🌕', ['full_moon']),
  EmojiEntry('🌙', ['crescent_moon']),
  EmojiEntry('🌛', ['first_quarter_moon_with_face']),
  EmojiEntry('🌟', ['star2']),
  EmojiEntry('🥒', ['cucumber']),
  EmojiEntry('🌠', ['stars']),
  EmojiEntry('🌰', ['chestnut']),
  EmojiEntry('🥑', ['avocado']),
  EmojiEntry('🌱', ['seedling']),
  EmojiEntry('🌴', ['palm_tree']),
  EmojiEntry('🌵', ['cactus']),
  EmojiEntry('🌷', ['tulip']),
  EmojiEntry('🌸', ['cherry_blossom']),
  EmojiEntry('🌹', ['rose']),
  EmojiEntry('🌺', ['hibiscus']),
  EmojiEntry('🌻', ['sunflower']),
  EmojiEntry('🌼', ['blossom']),
  EmojiEntry('🌽', ['corn']),
  EmojiEntry('🥐', ['croissant']),
  EmojiEntry('🌾', ['ear_of_rice']),
  EmojiEntry('🌿', ['herb']),
  EmojiEntry('🍀', ['four_leaf_clover']),
  EmojiEntry('🍁', ['maple_leaf']),
  EmojiEntry('🍂', ['fallen_leaf']),
  EmojiEntry('🍃', ['leaves']),
  EmojiEntry('🍄', ['mushroom']),
  EmojiEntry('🍅', ['tomato']),
  EmojiEntry('🍆', ['eggplant']),
  EmojiEntry('🍇', ['grapes']),
  EmojiEntry('🍈', ['melon']),
  EmojiEntry('🍉', ['watermelon']),
  EmojiEntry('🍊', ['tangerine']),
  EmojiEntry('🥀', ['wilted_rose', 'wilted_flower']),
  EmojiEntry('🍌', ['banana']),
  EmojiEntry('🍍', ['pineapple']),
  EmojiEntry('🍎', ['apple']),
  EmojiEntry('🍏', ['green_apple']),
  EmojiEntry('🍑', ['peach']),
  EmojiEntry('🍒', ['cherries']),
  EmojiEntry('🍓', ['strawberry']),
  EmojiEntry('🦏', ['rhino', 'rhinoceros']),
  EmojiEntry('🍔', ['hamburger']),
  EmojiEntry('🍕', ['pizza']),
  EmojiEntry('🍖', ['meat_on_bone']),
  EmojiEntry('🦎', ['lizard']),
  EmojiEntry('🍗', ['poultry_leg']),
  EmojiEntry('🍘', ['rice_cracker']),
  EmojiEntry('🍙', ['rice_ball']),
  EmojiEntry('🦍', ['gorilla']),
  EmojiEntry('🍚', ['rice']),
  EmojiEntry('🍛', ['curry']),
  EmojiEntry('🦌', ['deer']),
  EmojiEntry('🍜', ['ramen']),
  EmojiEntry('🍝', ['spaghetti']),
  EmojiEntry('🍞', ['bread']),
  EmojiEntry('🍟', ['fries']),
  EmojiEntry('🦋', ['butterfly']),
  EmojiEntry('🍠', ['sweet_potato']),
  EmojiEntry('🍡', ['dango']),
  EmojiEntry('🦊', ['fox', 'fox_face']),
  EmojiEntry('🍢', ['oden']),
  EmojiEntry('🍣', ['sushi']),
  EmojiEntry('🦉', ['owl']),
  EmojiEntry('🍤', ['fried_shrimp']),
  EmojiEntry('🍥', ['fish_cake']),
  EmojiEntry('🦈', ['shark']),
  EmojiEntry('🍦', ['icecream']),
  EmojiEntry('🦇', ['bat']),
  EmojiEntry('🍧', ['shaved_ice']),
  EmojiEntry('🇽', ['regional_indicator_x']),
  EmojiEntry('🍨', ['ice_cream']),
  EmojiEntry('🦆', ['duck']),
  EmojiEntry('🍩', ['doughnut']),
  EmojiEntry('🦅', ['eagle']),
  EmojiEntry('🍪', ['cookie']),
  EmojiEntry('🖤', ['black_heart']),
  EmojiEntry('🍫', ['chocolate_bar']),
  EmojiEntry('🍬', ['candy']),
  EmojiEntry('🍭', ['lollipop']),
  EmojiEntry('🍮', ['custard', 'pudding', 'flan']),
  EmojiEntry('🍯', ['honey_pot']),
  EmojiEntry('🤞', ['fingers_crossed', 'hand_with_index_and_middle_finger_crossed']),
  EmojiEntry('🍰', ['cake']),
  EmojiEntry('🍱', ['bento']),
  EmojiEntry('🍲', ['stew']),
  EmojiEntry('🤝', ['handshake', 'shaking_hands']),
  EmojiEntry('🍳', ['cooking']),
  EmojiEntry('🍴', ['fork_and_knife']),
  EmojiEntry('🍵', ['tea']),
  EmojiEntry('🍶', ['sake']),
  EmojiEntry('🍷', ['wine_glass']),
  EmojiEntry('🍸', ['cocktail']),
  EmojiEntry('🍹', ['tropical_drink']),
  EmojiEntry('🍺', ['beer']),
  EmojiEntry('🍻', ['beers']),
  EmojiEntry('🎀', ['ribbon']),
  EmojiEntry('🎁', ['gift']),
  EmojiEntry('🎂', ['birthday']),
  EmojiEntry('🎃', ['jack_o_lantern']),
  EmojiEntry('🤛', ['left_facing_fist', 'left_fist']),
  EmojiEntry('🤜', ['right_facing_fist', 'right_fist']),
  EmojiEntry('🎄', ['christmas_tree']),
  EmojiEntry('🎅', ['santa']),
  EmojiEntry('🎆', ['fireworks']),
  EmojiEntry('🤚', ['raised_back_of_hand', 'back_of_hand']),
  EmojiEntry('🎇', ['sparkler']),
  EmojiEntry('🎈', ['balloon']),
  EmojiEntry('🎉', ['tada']),
  EmojiEntry('🎊', ['confetti_ball']),
  EmojiEntry('🎋', ['tanabata_tree']),
  EmojiEntry('🎌', ['crossed_flags']),
  EmojiEntry('🤙', ['call_me', 'call_me_hand']),
  EmojiEntry('🎍', ['bamboo']),
  EmojiEntry('🕺', ['man_dancing', 'male_dancer']),
  EmojiEntry('🎎', ['dolls']),
  EmojiEntry('🤳', ['selfie']),
  EmojiEntry('🎏', ['flags']),
  EmojiEntry('🤰', ['pregnant_woman', 'expecting_woman']),
  EmojiEntry('🎐', ['wind_chime']),
  EmojiEntry('🤦', ['person_facepalming', 'face_palm', 'facepalm']),
  EmojiEntry('🤷', ['person_shrugging', 'shrug']),
  EmojiEntry('🎑', ['rice_scene']),
  EmojiEntry('🎒', ['school_satchel']),
  EmojiEntry('🎓', ['mortar_board']),
  EmojiEntry('🎠', ['carousel_horse']),
  EmojiEntry('🎡', ['ferris_wheel']),
  EmojiEntry('🎢', ['roller_coaster']),
  EmojiEntry('🎣', ['fishing_pole_and_fish']),
  EmojiEntry('🎤', ['microphone']),
  EmojiEntry('#️', ['pound_symbol']),
  EmojiEntry('🎥', ['movie_camera']),
  EmojiEntry('🎦', ['cinema']),
  EmojiEntry('🎧', ['headphones']),
  EmojiEntry('🤶', ['mrs_claus', 'mother_christmas']),
  EmojiEntry('🎨', ['art']),
  EmojiEntry('🤵', ['man_in_tuxedo']),
  EmojiEntry('🎩', ['tophat']),
  EmojiEntry('🎪', ['circus_tent']),
  EmojiEntry('🤴', ['prince']),
  EmojiEntry('🎫', ['ticket']),
  EmojiEntry('🎬', ['clapper']),
  EmojiEntry('🎭', ['performing_arts']),
  EmojiEntry('🤧', ['sneezing_face', 'sneeze']),
  EmojiEntry('🎮', ['video_game']),
  EmojiEntry('🎯', ['dart']),
  EmojiEntry('🎰', ['slot_machine']),
  EmojiEntry('🎱', ['8ball']),
  EmojiEntry('🎲', ['game_die']),
  EmojiEntry('🎳', ['bowling']),
  EmojiEntry('🎴', ['flower_playing_cards']),
  EmojiEntry('🤥', ['lying_face', 'liar']),
  EmojiEntry('🎵', ['musical_note']),
  EmojiEntry('🎶', ['notes']),
  EmojiEntry('🎷', ['saxophone']),
  EmojiEntry('🤤', ['drooling_face', 'drool']),
  EmojiEntry('🎸', ['guitar']),
  EmojiEntry('🎹', ['musical_keyboard']),
  EmojiEntry('🎺', ['trumpet']),
  EmojiEntry('🤣', ['rofl', 'rolling_on_the_floor_laughing']),
  EmojiEntry('🎻', ['violin']),
  EmojiEntry('🎼', ['musical_score']),
  EmojiEntry('🎽', ['running_shirt_with_sash']),
  EmojiEntry('🤢', ['nauseated_face', 'sick']),
  EmojiEntry('🎾', ['tennis']),
  EmojiEntry('🎿', ['ski']),
  EmojiEntry('🏀', ['basketball']),
  EmojiEntry('🏁', ['checkered_flag']),
  EmojiEntry('🤡', ['clown', 'clown_face']),
  EmojiEntry('🏂', ['snowboarder']),
  EmojiEntry('🏃', ['person_running', 'runner']),
  EmojiEntry('🏄', ['person_surfing', 'surfer']),
  EmojiEntry('🏆', ['trophy']),
  EmojiEntry('🏈', ['football']),
  EmojiEntry('🏊', ['person_swimming', 'swimmer']),
  EmojiEntry('🏠', ['house']),
  EmojiEntry('🏡', ['house_with_garden']),
  EmojiEntry('🏢', ['office']),
  EmojiEntry('🏣', ['post_office']),
  EmojiEntry('🏥', ['hospital']),
  EmojiEntry('🏦', ['bank']),
  EmojiEntry('🏧', ['atm']),
  EmojiEntry('🏨', ['hotel']),
  EmojiEntry('🏩', ['love_hotel']),
  EmojiEntry('🏪', ['convenience_store']),
  EmojiEntry('🏫', ['school']),
  EmojiEntry('🏬', ['department_store']),
  EmojiEntry('🤠', ['cowboy', 'face_with_cowboy_hat']),
  EmojiEntry('🏭', ['factory']),
  EmojiEntry('🏮', ['izakaya_lantern']),
  EmojiEntry('🏯', ['japanese_castle']),
  EmojiEntry('🏰', ['european_castle']),
  EmojiEntry('🐌', ['snail']),
  EmojiEntry('🐍', ['snake']),
  EmojiEntry('🐎', ['racehorse']),
  EmojiEntry('🐑', ['sheep']),
  EmojiEntry('🐒', ['monkey']),
  EmojiEntry('🐔', ['chicken']),
  EmojiEntry('🐗', ['boar']),
  EmojiEntry('🐘', ['elephant']),
  EmojiEntry('🐙', ['octopus']),
  EmojiEntry('🐚', ['shell']),
  EmojiEntry('🤴🏻', ['prince_tone1']),
  EmojiEntry('🐛', ['bug']),
  EmojiEntry('🐜', ['ant']),
  EmojiEntry('🐝', ['bee']),
  EmojiEntry('🐞', ['beetle']),
  EmojiEntry('🐟', ['fish']),
  EmojiEntry('🐠', ['tropical_fish']),
  EmojiEntry('🐡', ['blowfish']),
  EmojiEntry('🐢', ['turtle']),
  EmojiEntry('🐣', ['hatching_chick']),
  EmojiEntry('🐤', ['baby_chick']),
  EmojiEntry('🐥', ['hatched_chick']),
  EmojiEntry('🐦', ['bird']),
  EmojiEntry('🐧', ['penguin']),
  EmojiEntry('🐨', ['koala']),
  EmojiEntry('🐩', ['poodle']),
  EmojiEntry('🐫', ['camel']),
  EmojiEntry('🐬', ['dolphin']),
  EmojiEntry('🐭', ['mouse']),
  EmojiEntry('🐮', ['cow']),
  EmojiEntry('🐯', ['tiger']),
  EmojiEntry('🐰', ['rabbit']),
  EmojiEntry('🐱', ['cat']),
  EmojiEntry('🐲', ['dragon_face']),
  EmojiEntry('🐳', ['whale']),
  EmojiEntry('🐴', ['horse']),
  EmojiEntry('🐵', ['monkey_face']),
  EmojiEntry('🐶', ['dog']),
  EmojiEntry('🐷', ['pig']),
  EmojiEntry('🐸', ['frog']),
  EmojiEntry('🐹', ['hamster']),
  EmojiEntry('🐺', ['wolf']),
  EmojiEntry('🐻', ['bear']),
  EmojiEntry('🐼', ['panda_face']),
  EmojiEntry('🐽', ['pig_nose']),
  EmojiEntry('🐾', ['feet', 'paw_prints']),
  EmojiEntry('🤴🏼', ['prince_tone2']),
  EmojiEntry('👀', ['eyes']),
  EmojiEntry('👂', ['ear']),
  EmojiEntry('👃', ['nose']),
  EmojiEntry('👄', ['lips']),
  EmojiEntry('👅', ['tongue']),
  EmojiEntry('🤴🏽', ['prince_tone3']),
  EmojiEntry('👆', ['point_up_2']),
  EmojiEntry('👇', ['point_down']),
  EmojiEntry('👈', ['point_left']),
  EmojiEntry('👉', ['point_right']),
  EmojiEntry('👊', ['punch']),
  EmojiEntry('👋', ['wave']),
  EmojiEntry('👌', ['ok_hand']),
  EmojiEntry('👍', ['thumbsup', '+1', 'thumbup']),
  EmojiEntry('👎', ['thumbsdown', '-1', 'thumbdown']),
  EmojiEntry('👏', ['clap']),
  EmojiEntry('👐', ['open_hands']),
  EmojiEntry('👑', ['crown']),
  EmojiEntry('👒', ['womans_hat']),
  EmojiEntry('👓', ['eyeglasses']),
  EmojiEntry('👔', ['necktie']),
  EmojiEntry('👕', ['shirt']),
  EmojiEntry('🤴🏾', ['prince_tone4']),
  EmojiEntry('👖', ['jeans']),
  EmojiEntry('👗', ['dress']),
  EmojiEntry('👘', ['kimono']),
  EmojiEntry('🤴🏿', ['prince_tone5']),
  EmojiEntry('👙', ['bikini']),
  EmojiEntry('👚', ['womans_clothes']),
  EmojiEntry('👛', ['purse']),
  EmojiEntry('👜', ['handbag']),
  EmojiEntry('👝', ['pouch']),
  EmojiEntry('👞', ['mans_shoe']),
  EmojiEntry('👟', ['athletic_shoe']),
  EmojiEntry('👠', ['high_heel']),
  EmojiEntry('👡', ['sandal']),
  EmojiEntry('👢', ['boot']),
  EmojiEntry('👣', ['footprints']),
  EmojiEntry('👤', ['bust_in_silhouette']),
  EmojiEntry('🤶🏻', ['mrs_claus_tone1', 'mother_christmas_tone1']),
  EmojiEntry('👦', ['boy']),
  EmojiEntry('👧', ['girl']),
  EmojiEntry('👨', ['man']),
  EmojiEntry('👩', ['woman']),
  EmojiEntry('👪', ['family']),
  EmojiEntry('👫', ['couple']),
  EmojiEntry('👮', ['police_officer', 'cop']),
  EmojiEntry('👯', ['people_with_bunny_ears_partying', 'dancers']),
  EmojiEntry('👰', ['bride_with_veil']),
  EmojiEntry('👱', ['blond_haired_person', 'person_with_blond_hair']),
  EmojiEntry('👲', ['man_with_chinese_cap', 'man_with_gua_pi_mao']),
  EmojiEntry('👳', ['person_wearing_turban', 'man_with_turban']),
  EmojiEntry('👴', ['older_man']),
  EmojiEntry('👵', ['older_woman', 'grandma']),
  EmojiEntry('👶', ['baby']),
  EmojiEntry('👷', ['construction_worker']),
  EmojiEntry('👸', ['princess']),
  EmojiEntry('👹', ['japanese_ogre']),
  EmojiEntry('🤶🏼', ['mrs_claus_tone2', 'mother_christmas_tone2']),
  EmojiEntry('👺', ['japanese_goblin']),
  EmojiEntry('👻', ['ghost']),
  EmojiEntry('👼', ['angel']),
  EmojiEntry('👽', ['alien']),
  EmojiEntry('👾', ['space_invader']),
  EmojiEntry('🤶🏽', ['mrs_claus_tone3', 'mother_christmas_tone3']),
  EmojiEntry('👿', ['imp']),
  EmojiEntry('💀', ['skull', 'skeleton']),
  EmojiEntry('📇', ['card_index']),
  EmojiEntry('💁', ['person_tipping_hand', 'information_desk_person']),
  EmojiEntry('💂', ['guard', 'guardsman']),
  EmojiEntry('💃', ['dancer']),
  EmojiEntry('💄', ['lipstick']),
  EmojiEntry('💅', ['nail_care']),
  EmojiEntry('📒', ['ledger']),
  EmojiEntry('💆', ['person_getting_massage', 'massage']),
  EmojiEntry('📓', ['notebook']),
  EmojiEntry('💇', ['person_getting_haircut', 'haircut']),
  EmojiEntry('📔', ['notebook_with_decorative_cover']),
  EmojiEntry('💈', ['barber']),
  EmojiEntry('📕', ['closed_book']),
  EmojiEntry('💉', ['syringe']),
  EmojiEntry('📖', ['book']),
  EmojiEntry('💊', ['pill']),
  EmojiEntry('📗', ['green_book']),
  EmojiEntry('💋', ['kiss']),
  EmojiEntry('📘', ['blue_book']),
  EmojiEntry('💌', ['love_letter']),
  EmojiEntry('📙', ['orange_book']),
  EmojiEntry('💍', ['ring']),
  EmojiEntry('📚', ['books']),
  EmojiEntry('💎', ['gem']),
  EmojiEntry('🤶🏾', ['mrs_claus_tone4', 'mother_christmas_tone4']),
  EmojiEntry('📛', ['name_badge']),
  EmojiEntry('💏', ['couplekiss']),
  EmojiEntry('📜', ['scroll']),
  EmojiEntry('💐', ['bouquet']),
  EmojiEntry('📝', ['pencil', 'memo']),
  EmojiEntry('🤶🏿', ['mrs_claus_tone5', 'mother_christmas_tone5']),
  EmojiEntry('💑', ['couple_with_heart']),
  EmojiEntry('📞', ['telephone_receiver']),
  EmojiEntry('💒', ['wedding']),
  EmojiEntry('📟', ['pager']),
  EmojiEntry('📠', ['fax']),
  EmojiEntry('💓', ['heartbeat']),
  EmojiEntry('📡', ['satellite']),
  EmojiEntry('📢', ['loudspeaker']),
  EmojiEntry('🤵🏻', ['man_in_tuxedo_tone1', 'tuxedo_tone1']),
  EmojiEntry('💔', ['broken_heart']),
  EmojiEntry('📣', ['mega']),
  EmojiEntry('📤', ['outbox_tray']),
  EmojiEntry('💕', ['two_hearts']),
  EmojiEntry('📥', ['inbox_tray']),
  EmojiEntry('📦', ['package']),
  EmojiEntry('🤵🏼', ['man_in_tuxedo_tone2', 'tuxedo_tone2']),
  EmojiEntry('💖', ['sparkling_heart']),
  EmojiEntry('📧', ['e-mail', 'email']),
  EmojiEntry('📨', ['incoming_envelope']),
  EmojiEntry('💗', ['heartpulse']),
  EmojiEntry('🤵🏽', ['man_in_tuxedo_tone3', 'tuxedo_tone3']),
  EmojiEntry('📩', ['envelope_with_arrow']),
  EmojiEntry('📪', ['mailbox_closed']),
  EmojiEntry('💘', ['cupid']),
  EmojiEntry('📫', ['mailbox']),
  EmojiEntry('🤵🏾', ['man_in_tuxedo_tone4', 'tuxedo_tone4']),
  EmojiEntry('📮', ['postbox']),
  EmojiEntry('💙', ['blue_heart']),
  EmojiEntry('📰', ['newspaper']),
  EmojiEntry('🤵🏿', ['man_in_tuxedo_tone5', 'tuxedo_tone5']),
  EmojiEntry('📱', ['iphone']),
  EmojiEntry('💚', ['green_heart']),
  EmojiEntry('🤷🏻', ['person_shrugging_tone1', 'shrug_tone1']),
  EmojiEntry('📲', ['calling']),
  EmojiEntry('📳', ['vibration_mode']),
  EmojiEntry('💛', ['yellow_heart']),
  EmojiEntry('🤷🏼', ['person_shrugging_tone2', 'shrug_tone2']),
  EmojiEntry('📴', ['mobile_phone_off']),
  EmojiEntry('📶', ['signal_strength']),
  EmojiEntry('🤷🏽', ['person_shrugging_tone3', 'shrug_tone3']),
  EmojiEntry('💜', ['purple_heart']),
  EmojiEntry('🤷🏾', ['person_shrugging_tone4', 'shrug_tone4']),
  EmojiEntry('📷', ['camera']),
  EmojiEntry('📹', ['video_camera']),
  EmojiEntry('💝', ['gift_heart']),
  EmojiEntry('📺', ['tv']),
  EmojiEntry('🤷🏿', ['person_shrugging_tone5', 'shrug_tone5']),
  EmojiEntry('📻', ['radio']),
  EmojiEntry('💞', ['revolving_hearts']),
  EmojiEntry('📼', ['vhs']),
  EmojiEntry('🤦🏻', ['person_facepalming_tone1', 'face_palm_tone1', 'facepalm_tone1']),
  EmojiEntry('🔃', ['arrows_clockwise']),
  EmojiEntry('💟', ['heart_decoration']),
  EmojiEntry('🔊', ['loud_sound']),
  EmojiEntry('🔋', ['battery']),
  EmojiEntry('💠', ['diamond_shape_with_a_dot_inside']),
  EmojiEntry('🔌', ['electric_plug']),
  EmojiEntry('🔍', ['mag']),
  EmojiEntry('🤦🏼', ['person_facepalming_tone2', 'face_palm_tone2', 'facepalm_tone2']),
  EmojiEntry('💡', ['bulb']),
  EmojiEntry('🔎', ['mag_right']),
  EmojiEntry('🔏', ['lock_with_ink_pen']),
  EmojiEntry('💢', ['anger']),
  EmojiEntry('🔐', ['closed_lock_with_key']),
  EmojiEntry('🔑', ['key']),
  EmojiEntry('💣', ['bomb']),
  EmojiEntry('🔒', ['lock']),
  EmojiEntry('🔓', ['unlock']),
  EmojiEntry('💤', ['zzz']),
  EmojiEntry('🔔', ['bell']),
  EmojiEntry('🔖', ['bookmark']),
  EmojiEntry('💥', ['boom']),
  EmojiEntry('🤦🏽', ['person_facepalming_tone3', 'face_palm_tone3', 'facepalm_tone3']),
  EmojiEntry('🔗', ['link']),
  EmojiEntry('🔘', ['radio_button']),
  EmojiEntry('💦', ['sweat_drops']),
  EmojiEntry('🔙', ['back']),
  EmojiEntry('🔚', ['end']),
  EmojiEntry('💧', ['droplet']),
  EmojiEntry('🤦🏾', ['person_facepalming_tone4', 'face_palm_tone4', 'facepalm_tone4']),
  EmojiEntry('🔛', ['on']),
  EmojiEntry('🔜', ['soon']),
  EmojiEntry('💨', ['dash']),
  EmojiEntry('🔝', ['top']),
  EmojiEntry('🔞', ['underage']),
  EmojiEntry('💩', ['poop', 'shit', 'hankey', 'poo']),
  EmojiEntry('🔟', ['keycap_ten']),
  EmojiEntry('💪', ['muscle']),
  EmojiEntry('🔠', ['capital_abcd']),
  EmojiEntry('🔡', ['abcd']),
  EmojiEntry('💫', ['dizzy']),
  EmojiEntry('🤦🏿', ['person_facepalming_tone5', 'face_palm_tone5', 'facepalm_tone5']),
  EmojiEntry('🔢', ['1234']),
  EmojiEntry('🔣', ['symbols']),
  EmojiEntry('💬', ['speech_balloon']),
  EmojiEntry('🔤', ['abc']),
  EmojiEntry('🔥', ['fire', 'flame']),
  EmojiEntry('💮', ['white_flower']),
  EmojiEntry('🔦', ['flashlight']),
  EmojiEntry('🔧', ['wrench']),
  EmojiEntry('💯', ['100']),
  EmojiEntry('🔨', ['hammer']),
  EmojiEntry('🔩', ['nut_and_bolt']),
  EmojiEntry('💰', ['moneybag']),
  EmojiEntry('🔪', ['knife']),
  EmojiEntry('🔫', ['gun']),
  EmojiEntry('💱', ['currency_exchange']),
  EmojiEntry('🤰🏻', ['pregnant_woman_tone1', 'expecting_woman_tone1']),
  EmojiEntry('🔮', ['crystal_ball']),
  EmojiEntry('💲', ['heavy_dollar_sign']),
  EmojiEntry('🔯', ['six_pointed_star']),
  EmojiEntry('💳', ['credit_card']),
  EmojiEntry('🔰', ['beginner']),
  EmojiEntry('🔱', ['trident']),
  EmojiEntry('💴', ['yen']),
  EmojiEntry('🤰🏼', ['pregnant_woman_tone2', 'expecting_woman_tone2']),
  EmojiEntry('🔲', ['black_square_button']),
  EmojiEntry('🔳', ['white_square_button']),
  EmojiEntry('💵', ['dollar']),
  EmojiEntry('🔴', ['red_circle']),
  EmojiEntry('🔵', ['blue_circle']),
  EmojiEntry('💸', ['money_with_wings']),
  EmojiEntry('🔶', ['large_orange_diamond']),
  EmojiEntry('🔷', ['large_blue_diamond']),
  EmojiEntry('💹', ['chart']),
  EmojiEntry('🤰🏽', ['pregnant_woman_tone3', 'expecting_woman_tone3']),
  EmojiEntry('🔸', ['small_orange_diamond']),
  EmojiEntry('🔹', ['small_blue_diamond']),
  EmojiEntry('💺', ['seat']),
  EmojiEntry('🔺', ['small_red_triangle']),
  EmojiEntry('🔻', ['small_red_triangle_down']),
  EmojiEntry('💻', ['computer']),
  EmojiEntry('🔼', ['arrow_up_small']),
  EmojiEntry('💼', ['briefcase']),
  EmojiEntry('🔽', ['arrow_down_small']),
  EmojiEntry('🕐', ['clock1']),
  EmojiEntry('💽', ['minidisc']),
  EmojiEntry('🕑', ['clock2']),
  EmojiEntry('💾', ['floppy_disk']),
  EmojiEntry('🤰🏾', ['pregnant_woman_tone4', 'expecting_woman_tone4']),
  EmojiEntry('🕒', ['clock3']),
  EmojiEntry('💿', ['cd']),
  EmojiEntry('🕓', ['clock4']),
  EmojiEntry('📀', ['dvd']),
  EmojiEntry('🕔', ['clock5']),
  EmojiEntry('🕕', ['clock6']),
  EmojiEntry('📁', ['file_folder']),
  EmojiEntry('🕖', ['clock7']),
  EmojiEntry('🕗', ['clock8']),
  EmojiEntry('📂', ['open_file_folder']),
  EmojiEntry('🕘', ['clock9']),
  EmojiEntry('🕙', ['clock10']),
  EmojiEntry('📃', ['page_with_curl']),
  EmojiEntry('🕚', ['clock11']),
  EmojiEntry('🕛', ['clock12']),
  EmojiEntry('📄', ['page_facing_up']),
  EmojiEntry('🗻', ['mount_fuji']),
  EmojiEntry('🗼', ['tokyo_tower']),
  EmojiEntry('📅', ['date']),
  EmojiEntry('🗽', ['statue_of_liberty']),
  EmojiEntry('🗾', ['japan']),
  EmojiEntry('📆', ['calendar']),
  EmojiEntry('🗿', ['moyai']),
  EmojiEntry('😁', ['grin']),
  EmojiEntry('😂', ['joy']),
  EmojiEntry('😃', ['smiley']),
  EmojiEntry('📈', ['chart_with_upwards_trend']),
  EmojiEntry('😄', ['smile']),
  EmojiEntry('😅', ['sweat_smile']),
  EmojiEntry('📉', ['chart_with_downwards_trend']),
  EmojiEntry('😆', ['laughing', 'satisfied']),
  EmojiEntry('😉', ['wink']),
  EmojiEntry('📊', ['bar_chart']),
  EmojiEntry('😊', ['blush']),
  EmojiEntry('😋', ['yum']),
  EmojiEntry('📋', ['clipboard']),
  EmojiEntry('😌', ['relieved']),
  EmojiEntry('😍', ['heart_eyes']),
  EmojiEntry('📌', ['pushpin']),
  EmojiEntry('😏', ['smirk']),
  EmojiEntry('😒', ['unamused']),
  EmojiEntry('📍', ['round_pushpin']),
  EmojiEntry('😓', ['sweat']),
  EmojiEntry('😔', ['pensive']),
  EmojiEntry('📎', ['paperclip']),
  EmojiEntry('😖', ['confounded']),
  EmojiEntry('😘', ['kissing_heart']),
  EmojiEntry('🤰🏿', ['pregnant_woman_tone5', 'expecting_woman_tone5']),
  EmojiEntry('📏', ['straight_ruler']),
  EmojiEntry('😚', ['kissing_closed_eyes']),
  EmojiEntry('😜', ['stuck_out_tongue_winking_eye']),
  EmojiEntry('📐', ['triangular_ruler']),
  EmojiEntry('😝', ['stuck_out_tongue_closed_eyes']),
  EmojiEntry('😞', ['disappointed']),
  EmojiEntry('📑', ['bookmark_tabs']),
  EmojiEntry('😠', ['angry']),
  EmojiEntry('😡', ['rage']),
  EmojiEntry('😢', ['cry']),
  EmojiEntry('😣', ['persevere']),
  EmojiEntry('😤', ['triumph']),
  EmojiEntry('😥', ['disappointed_relieved']),
  EmojiEntry('😨', ['fearful']),
  EmojiEntry('😩', ['weary']),
  EmojiEntry('😪', ['sleepy']),
  EmojiEntry('😫', ['tired_face']),
  EmojiEntry('😭', ['sob']),
  EmojiEntry('😰', ['cold_sweat']),
  EmojiEntry('😱', ['scream']),
  EmojiEntry('😲', ['astonished']),
  EmojiEntry('😳', ['flushed']),
  EmojiEntry('😵', ['dizzy_face']),
  EmojiEntry('😷', ['mask']),
  EmojiEntry('😸', ['smile_cat']),
  EmojiEntry('😹', ['joy_cat']),
  EmojiEntry('😺', ['smiley_cat']),
  EmojiEntry('😻', ['heart_eyes_cat']),
  EmojiEntry('😼', ['smirk_cat']),
  EmojiEntry('😽', ['kissing_cat']),
  EmojiEntry('😾', ['pouting_cat']),
  EmojiEntry('😿', ['crying_cat_face']),
  EmojiEntry('🙀', ['scream_cat']),
  EmojiEntry('🙅', ['person_gesturing_no', 'no_good']),
  EmojiEntry('🙆', ['person_gesturing_ok', 'ok_woman']),
  EmojiEntry('🙇', ['person_bowing', 'bow']),
  EmojiEntry('🙈', ['see_no_evil']),
  EmojiEntry('🕺🏻', ['man_dancing_tone1', 'male_dancer_tone1']),
  EmojiEntry('🙉', ['hear_no_evil']),
  EmojiEntry('🙊', ['speak_no_evil']),
  EmojiEntry('🕺🏼', ['man_dancing_tone2', 'male_dancer_tone2']),
  EmojiEntry('🙋', ['person_raising_hand', 'raising_hand']),
  EmojiEntry('🙌', ['raised_hands']),
  EmojiEntry('🙍', ['person_frowning']),
  EmojiEntry('🙎', ['person_pouting', 'person_with_pouting_face']),
  EmojiEntry('🙏', ['pray']),
  EmojiEntry('🚀', ['rocket']),
  EmojiEntry('🚃', ['railway_car']),
  EmojiEntry('🚄', ['bullettrain_side']),
  EmojiEntry('🚅', ['bullettrain_front']),
  EmojiEntry('🚇', ['metro']),
  EmojiEntry('🚉', ['station']),
  EmojiEntry('🚌', ['bus']),
  EmojiEntry('🚏', ['busstop']),
  EmojiEntry('🚑', ['ambulance']),
  EmojiEntry('🚒', ['fire_engine']),
  EmojiEntry('🚓', ['police_car']),
  EmojiEntry('🚕', ['taxi']),
  EmojiEntry('🚗', ['red_car']),
  EmojiEntry('🚙', ['blue_car']),
  EmojiEntry('🚚', ['truck']),
  EmojiEntry('🚢', ['ship']),
  EmojiEntry('🚤', ['speedboat']),
  EmojiEntry('🚥', ['traffic_light']),
  EmojiEntry('🚧', ['construction']),
  EmojiEntry('🚨', ['rotating_light']),
  EmojiEntry('🚩', ['triangular_flag_on_post']),
  EmojiEntry('🚪', ['door']),
  EmojiEntry('🕺🏽', ['man_dancing_tone3', 'male_dancer_tone3']),
  EmojiEntry('🚫', ['no_entry_sign']),
  EmojiEntry('🚬', ['smoking']),
  EmojiEntry('🚭', ['no_smoking']),
  EmojiEntry('🚲', ['bike']),
  EmojiEntry('🚶', ['person_walking', 'walking']),
  EmojiEntry('🚹', ['mens']),
  EmojiEntry('🚺', ['womens']),
  EmojiEntry('🕺🏾', ['man_dancing_tone4', 'male_dancer_tone4']),
  EmojiEntry('🚻', ['restroom']),
  EmojiEntry('🚼', ['baby_symbol']),
  EmojiEntry('🕺🏿', ['man_dancing_tone5', 'male_dancer_tone5']),
  EmojiEntry('🚽', ['toilet']),
  EmojiEntry('🚾', ['wc']),
  EmojiEntry('🤳🏻', ['selfie_tone1']),
  EmojiEntry('🛀', ['bath']),
  EmojiEntry('🤘', ['metal', 'sign_of_the_horns']),
  EmojiEntry('😀', ['grinning']),
  EmojiEntry('😇', ['innocent']),
  EmojiEntry('😈', ['smiling_imp']),
  EmojiEntry('😎', ['sunglasses']),
  EmojiEntry('😐', ['neutral_face']),
  EmojiEntry('😑', ['expressionless']),
  EmojiEntry('😕', ['confused']),
  EmojiEntry('😗', ['kissing']),
  EmojiEntry('🤳🏼', ['selfie_tone2']),
  EmojiEntry('😙', ['kissing_smiling_eyes']),
  EmojiEntry('😛', ['stuck_out_tongue']),
  EmojiEntry('😟', ['worried']),
  EmojiEntry('😦', ['frowning']),
  EmojiEntry('😧', ['anguished']),
  EmojiEntry('😬', ['grimacing']),
  EmojiEntry('😮', ['open_mouth']),
  EmojiEntry('😯', ['hushed']),
  EmojiEntry('😴', ['sleeping']),
  EmojiEntry('😶', ['no_mouth']),
  EmojiEntry('🚁', ['helicopter']),
  EmojiEntry('🚂', ['steam_locomotive']),
  EmojiEntry('🚆', ['train2']),
  EmojiEntry('🚈', ['light_rail']),
  EmojiEntry('🚊', ['tram']),
  EmojiEntry('🚍', ['oncoming_bus']),
  EmojiEntry('🚎', ['trolleybus']),
  EmojiEntry('🚐', ['minibus']),
  EmojiEntry('🚔', ['oncoming_police_car']),
  EmojiEntry('🚖', ['oncoming_taxi']),
  EmojiEntry('🚘', ['oncoming_automobile']),
  EmojiEntry('🚛', ['articulated_lorry']),
  EmojiEntry('🤳🏽', ['selfie_tone3']),
  EmojiEntry('🚜', ['tractor']),
  EmojiEntry('🚝', ['monorail']),
  EmojiEntry('🚞', ['mountain_railway']),
  EmojiEntry('🚟', ['suspension_railway']),
  EmojiEntry('🚠', ['mountain_cableway']),
  EmojiEntry('🚡', ['aerial_tramway']),
  EmojiEntry('🚣', ['person_rowing_boat', 'rowboat']),
  EmojiEntry('🚦', ['vertical_traffic_light']),
  EmojiEntry('🤳🏾', ['selfie_tone4']),
  EmojiEntry('🚮', ['put_litter_in_its_place']),
  EmojiEntry('🚯', ['do_not_litter']),
  EmojiEntry('🤳🏿', ['selfie_tone5']),
  EmojiEntry('🚰', ['potable_water']),
  EmojiEntry('🚱', ['non-potable_water']),
  EmojiEntry('🚳', ['no_bicycles']),
  EmojiEntry('🤞🏻', ['fingers_crossed_tone1', 'hand_with_index_and_middle_fingers_crossed_tone1']),
  EmojiEntry('🚴', ['person_biking', 'bicyclist']),
  EmojiEntry('🚵', ['person_mountain_biking', 'mountain_bicyclist']),
  EmojiEntry('🚷', ['no_pedestrians']),
  EmojiEntry('🚸', ['children_crossing']),
  EmojiEntry('🚿', ['shower']),
  EmojiEntry('🛁', ['bathtub']),
  EmojiEntry('🛂', ['passport_control']),
  EmojiEntry('🤞🏼', ['fingers_crossed_tone2', 'hand_with_index_and_middle_fingers_crossed_tone2']),
  EmojiEntry('🛃', ['customs']),
  EmojiEntry('🛄', ['baggage_claim']),
  EmojiEntry('🤞🏽', ['fingers_crossed_tone3', 'hand_with_index_and_middle_fingers_crossed_tone3']),
  EmojiEntry('🛅', ['left_luggage']),
  EmojiEntry('🌍', ['earth_africa']),
  EmojiEntry('🌎', ['earth_americas']),
  EmojiEntry('🌐', ['globe_with_meridians']),
  EmojiEntry('🌒', ['waxing_crescent_moon']),
  EmojiEntry('🌖', ['waning_gibbous_moon']),
  EmojiEntry('🌗', ['last_quarter_moon']),
  EmojiEntry('🌘', ['waning_crescent_moon']),
  EmojiEntry('🌚', ['new_moon_with_face']),
  EmojiEntry('🌜', ['last_quarter_moon_with_face']),
  EmojiEntry('🌝', ['full_moon_with_face']),
  EmojiEntry('🌞', ['sun_with_face']),
  EmojiEntry('🌲', ['evergreen_tree']),
  EmojiEntry('🌳', ['deciduous_tree']),
  EmojiEntry('🍋', ['lemon']),
  EmojiEntry('🤞🏾', ['fingers_crossed_tone4', 'hand_with_index_and_middle_fingers_crossed_tone4']),
  EmojiEntry('🍐', ['pear']),
  EmojiEntry('🍼', ['baby_bottle']),
  EmojiEntry('🏇', ['horse_racing']),
  EmojiEntry('🏉', ['rugby_football']),
  EmojiEntry('🏤', ['european_post_office']),
  EmojiEntry('🐀', ['rat']),
  EmojiEntry('🐁', ['mouse2']),
  EmojiEntry('🐂', ['ox']),
  EmojiEntry('🐃', ['water_buffalo']),
  EmojiEntry('🐄', ['cow2']),
  EmojiEntry('🐅', ['tiger2']),
  EmojiEntry('🐆', ['leopard']),
  EmojiEntry('🐇', ['rabbit2']),
  EmojiEntry('🐈', ['cat2']),
  EmojiEntry('🐉', ['dragon']),
  EmojiEntry('🐊', ['crocodile']),
  EmojiEntry('🐋', ['whale2']),
  EmojiEntry('🐏', ['ram']),
  EmojiEntry('🐐', ['goat']),
  EmojiEntry('🐓', ['rooster']),
  EmojiEntry('🐕', ['dog2']),
  EmojiEntry('🐖', ['pig2']),
  EmojiEntry('🤞🏿', ['fingers_crossed_tone5', 'hand_with_index_and_middle_fingers_crossed_tone5']),
  EmojiEntry('🐪', ['dromedary_camel']),
  EmojiEntry('👥', ['busts_in_silhouette']),
  EmojiEntry('👬', ['two_men_holding_hands']),
  EmojiEntry('👭', ['two_women_holding_hands']),
  EmojiEntry('💭', ['thought_balloon']),
  EmojiEntry('💶', ['euro']),
  EmojiEntry('🤙🏻', ['call_me_tone1', 'call_me_hand_tone1']),
  EmojiEntry('💷', ['pound']),
  EmojiEntry('📬', ['mailbox_with_mail']),
  EmojiEntry('📭', ['mailbox_with_no_mail']),
  EmojiEntry('🤙🏼', ['call_me_tone2', 'call_me_hand_tone2']),
  EmojiEntry('📯', ['postal_horn']),
  EmojiEntry('📵', ['no_mobile_phones']),
  EmojiEntry('🔀', ['twisted_rightwards_arrows']),
  EmojiEntry('🔁', ['repeat']),
  EmojiEntry('🔂', ['repeat_one']),
  EmojiEntry('🔄', ['arrows_counterclockwise']),
  EmojiEntry('🤙🏽', ['call_me_tone3', 'call_me_hand_tone3']),
  EmojiEntry('🔅', ['low_brightness']),
  EmojiEntry('🔆', ['high_brightness']),
  EmojiEntry('🔇', ['mute']),
  EmojiEntry('🔉', ['sound']),
  EmojiEntry('🔕', ['no_bell']),
  EmojiEntry('🔬', ['microscope']),
  EmojiEntry('🔭', ['telescope']),
  EmojiEntry('🕜', ['clock130']),
  EmojiEntry('🕝', ['clock230']),
  EmojiEntry('🕞', ['clock330']),
  EmojiEntry('🕟', ['clock430']),
  EmojiEntry('🕠', ['clock530']),
  EmojiEntry('🕡', ['clock630']),
  EmojiEntry('🕢', ['clock730']),
  EmojiEntry('🕣', ['clock830']),
  EmojiEntry('🕤', ['clock930']),
  EmojiEntry('🕥', ['clock1030']),
  EmojiEntry('🕦', ['clock1130']),
  EmojiEntry('🕧', ['clock1230']),
  EmojiEntry('🔈', ['speaker']),
  EmojiEntry('🚋', ['train']),
  EmojiEntry('➿', ['loop']),
  EmojiEntry('🇦🇫', ['flag_af', 'af']),
  EmojiEntry('🇦🇱', ['flag_al', 'al']),
  EmojiEntry('🇩🇿', ['flag_dz', 'dz']),
  EmojiEntry('🇦🇩', ['flag_ad', 'ad']),
  EmojiEntry('🇦🇴', ['flag_ao', 'ao']),
  EmojiEntry('🇦🇬', ['flag_ag', 'ag']),
  EmojiEntry('🇦🇷', ['flag_ar', 'ar']),
  EmojiEntry('🇦🇲', ['flag_am', 'am']),
  EmojiEntry('🇦🇺', ['flag_au', 'au']),
  EmojiEntry('🇦🇹', ['flag_at', 'at']),
  EmojiEntry('🇦🇿', ['flag_az', 'az']),
  EmojiEntry('🇧🇸', ['flag_bs', 'bs']),
  EmojiEntry('🇧🇭', ['flag_bh', 'bh']),
  EmojiEntry('🇧🇩', ['flag_bd', 'bd']),
  EmojiEntry('🇧🇧', ['flag_bb', 'bb']),
  EmojiEntry('🇧🇾', ['flag_by', 'by']),
  EmojiEntry('🇧🇪', ['flag_be', 'be']),
  EmojiEntry('🇧🇿', ['flag_bz', 'bz']),
  EmojiEntry('🇧🇯', ['flag_bj', 'bj']),
  EmojiEntry('🇧🇹', ['flag_bt', 'bt']),
  EmojiEntry('🇧🇴', ['flag_bo', 'bo']),
  EmojiEntry('🇧🇦', ['flag_ba', 'ba']),
  EmojiEntry('🇧🇼', ['flag_bw', 'bw']),
  EmojiEntry('🇧🇷', ['flag_br', 'br']),
  EmojiEntry('🇧🇳', ['flag_bn', 'bn']),
  EmojiEntry('🇧🇬', ['flag_bg', 'bg']),
  EmojiEntry('🇧🇫', ['flag_bf', 'bf']),
  EmojiEntry('🇧🇮', ['flag_bi', 'bi']),
  EmojiEntry('🇰🇭', ['flag_kh', 'kh']),
  EmojiEntry('🇨🇲', ['flag_cm', 'cm']),
  EmojiEntry('🇨🇦', ['flag_ca', 'ca']),
  EmojiEntry('🇨🇻', ['flag_cv', 'cv']),
  EmojiEntry('🤙🏾', ['call_me_tone4', 'call_me_hand_tone4']),
  EmojiEntry('🇨🇫', ['flag_cf', 'cf']),
  EmojiEntry('🇹🇩', ['flag_td', 'td']),
  EmojiEntry('🇨🇱', ['flag_cl', 'chile']),
  EmojiEntry('🇨🇴', ['flag_co', 'co']),
  EmojiEntry('🇰🇲', ['flag_km', 'km']),
  EmojiEntry('🇨🇷', ['flag_cr', 'cr']),
  EmojiEntry('🇨🇮', ['flag_ci', 'ci']),
  EmojiEntry('🇭🇷', ['flag_hr', 'hr']),
  EmojiEntry('🇨🇺', ['flag_cu', 'cu']),
  EmojiEntry('🇨🇾', ['flag_cy', 'cy']),
  EmojiEntry('🇨🇿', ['flag_cz', 'cz']),
  EmojiEntry('🤙🏿', ['call_me_tone5', 'call_me_hand_tone5']),
  EmojiEntry('🇨🇩', ['flag_cd', 'congo']),
  EmojiEntry('🤛🏻', ['left_facing_fist_tone1', 'left_fist_tone1']),
  EmojiEntry('🇩🇰', ['flag_dk', 'dk']),
  EmojiEntry('🇩🇯', ['flag_dj', 'dj']),
  EmojiEntry('🇩🇲', ['flag_dm', 'dm']),
  EmojiEntry('🇩🇴', ['flag_do', 'do']),
  EmojiEntry('🇹🇱', ['flag_tl', 'tl']),
  EmojiEntry('🇪🇨', ['flag_ec', 'ec']),
  EmojiEntry('🇪🇬', ['flag_eg', 'eg']),
  EmojiEntry('🇸🇻', ['flag_sv', 'sv']),
  EmojiEntry('🇬🇶', ['flag_gq', 'gq']),
  EmojiEntry('🇪🇷', ['flag_er', 'er']),
  EmojiEntry('🇪🇪', ['flag_ee', 'ee']),
  EmojiEntry('🇪🇹', ['flag_et', 'et']),
  EmojiEntry('🤛🏼', ['left_facing_fist_tone2', 'left_fist_tone2']),
  EmojiEntry('🇫🇯', ['flag_fj', 'fj']),
  EmojiEntry('🇫🇮', ['flag_fi', 'fi']),
  EmojiEntry('🇬🇦', ['flag_ga', 'ga']),
  EmojiEntry('🇬🇲', ['flag_gm', 'gm']),
  EmojiEntry('🇬🇪', ['flag_ge', 'ge']),
  EmojiEntry('🇬🇭', ['flag_gh', 'gh']),
  EmojiEntry('🇬🇷', ['flag_gr', 'gr']),
  EmojiEntry('🇬🇩', ['flag_gd', 'gd']),
  EmojiEntry('🇬🇹', ['flag_gt', 'gt']),
  EmojiEntry('🇬🇳', ['flag_gn', 'gn']),
  EmojiEntry('🇬🇼', ['flag_gw', 'gw']),
  EmojiEntry('🇬🇾', ['flag_gy', 'gy']),
  EmojiEntry('🇭🇹', ['flag_ht', 'ht']),
  EmojiEntry('🇭🇳', ['flag_hn', 'hn']),
  EmojiEntry('🇭🇺', ['flag_hu', 'hu']),
  EmojiEntry('🇮🇸', ['flag_is', 'is']),
  EmojiEntry('🇮🇳', ['flag_in', 'in']),
  EmojiEntry('🇮🇩', ['flag_id', 'indonesia']),
  EmojiEntry('🇮🇷', ['flag_ir', 'ir']),
  EmojiEntry('🇮🇶', ['flag_iq', 'iq']),
  EmojiEntry('🇮🇪', ['flag_ie', 'ie']),
  EmojiEntry('🇮🇱', ['flag_il', 'il']),
  EmojiEntry('🇯🇲', ['flag_jm', 'jm']),
  EmojiEntry('🇯🇴', ['flag_jo', 'jo']),
  EmojiEntry('🇰🇿', ['flag_kz', 'kz']),
  EmojiEntry('🇰🇪', ['flag_ke', 'ke']),
  EmojiEntry('🇰🇮', ['flag_ki', 'ki']),
  EmojiEntry('🇽🇰', ['flag_xk', 'xk']),
  EmojiEntry('🇰🇼', ['flag_kw', 'kw']),
  EmojiEntry('🇰🇬', ['flag_kg', 'kg']),
  EmojiEntry('🤛🏽', ['left_facing_fist_tone3', 'left_fist_tone3']),
  EmojiEntry('🇱🇦', ['flag_la', 'la']),
  EmojiEntry('🇱🇻', ['flag_lv', 'lv']),
  EmojiEntry('🇱🇧', ['flag_lb', 'lb']),
  EmojiEntry('🇱🇸', ['flag_ls', 'ls']),
  EmojiEntry('🇱🇷', ['flag_lr', 'lr']),
  EmojiEntry('🇱🇾', ['flag_ly', 'ly']),
  EmojiEntry('🇱🇮', ['flag_li', 'li']),
  EmojiEntry('🇱🇹', ['flag_lt', 'lt']),
  EmojiEntry('🇱🇺', ['flag_lu', 'lu']),
  EmojiEntry('🇲🇰', ['flag_mk', 'mk']),
  EmojiEntry('🇲🇬', ['flag_mg', 'mg']),
  EmojiEntry('🇲🇼', ['flag_mw', 'mw']),
  EmojiEntry('🇲🇾', ['flag_my', 'my']),
  EmojiEntry('🇲🇻', ['flag_mv', 'mv']),
  EmojiEntry('🇲🇱', ['flag_ml', 'ml']),
  EmojiEntry('🇲🇹', ['flag_mt', 'mt']),
  EmojiEntry('🇲🇭', ['flag_mh', 'mh']),
  EmojiEntry('🇲🇷', ['flag_mr', 'mr']),
  EmojiEntry('🇲🇺', ['flag_mu', 'mu']),
  EmojiEntry('🇲🇽', ['flag_mx', 'mx']),
  EmojiEntry('🇫🇲', ['flag_fm', 'fm']),
  EmojiEntry('🇲🇩', ['flag_md', 'md']),
  EmojiEntry('🇲🇨', ['flag_mc', 'mc']),
  EmojiEntry('🇲🇳', ['flag_mn', 'mn']),
  EmojiEntry('🇲🇪', ['flag_me', 'me']),
  EmojiEntry('🇲🇦', ['flag_ma', 'ma']),
  EmojiEntry('🇲🇿', ['flag_mz', 'mz']),
  EmojiEntry('🇲🇲', ['flag_mm', 'mm']),
  EmojiEntry('🇳🇦', ['flag_na', 'na']),
  EmojiEntry('🇳🇷', ['flag_nr', 'nr']),
  EmojiEntry('🇳🇵', ['flag_np', 'np']),
  EmojiEntry('🇳🇱', ['flag_nl', 'nl']),
  EmojiEntry('🇳🇿', ['flag_nz', 'nz']),
  EmojiEntry('🇳🇮', ['flag_ni', 'ni']),
  EmojiEntry('🇳🇪', ['flag_ne', 'ne']),
  EmojiEntry('🇳🇬', ['flag_ng', 'nigeria']),
  EmojiEntry('🇰🇵', ['flag_kp', 'kp']),
  EmojiEntry('🇳🇴', ['flag_no', 'no']),
  EmojiEntry('🇴🇲', ['flag_om', 'om']),
  EmojiEntry('🇵🇰', ['flag_pk', 'pk']),
  EmojiEntry('🇵🇼', ['flag_pw', 'pw']),
  EmojiEntry('🇵🇦', ['flag_pa', 'pa']),
  EmojiEntry('🇵🇬', ['flag_pg', 'pg']),
  EmojiEntry('🤛🏾', ['left_facing_fist_tone4', 'left_fist_tone4']),
  EmojiEntry('🇵🇾', ['flag_py', 'py']),
  EmojiEntry('🇵🇪', ['flag_pe', 'pe']),
  EmojiEntry('🇵🇭', ['flag_ph', 'ph']),
  EmojiEntry('🇵🇱', ['flag_pl', 'pl']),
  EmojiEntry('🇵🇹', ['flag_pt', 'pt']),
  EmojiEntry('🇶🇦', ['flag_qa', 'qa']),
  EmojiEntry('🇹🇼', ['flag_tw', 'tw']),
  EmojiEntry('🇨🇬', ['flag_cg', 'cg']),
  EmojiEntry('🇷🇴', ['flag_ro', 'ro']),
  EmojiEntry('🇷🇼', ['flag_rw', 'rw']),
  EmojiEntry('🇰🇳', ['flag_kn', 'kn']),
  EmojiEntry('🇱🇨', ['flag_lc', 'lc']),
  EmojiEntry('🇻🇨', ['flag_vc', 'vc']),
  EmojiEntry('🇼🇸', ['flag_ws', 'ws']),
  EmojiEntry('🇸🇲', ['flag_sm', 'sm']),
  EmojiEntry('🇸🇹', ['flag_st', 'st']),
  EmojiEntry('🇸🇦', ['flag_sa', 'saudiarabia', 'saudi']),
  EmojiEntry('🤛🏿', ['left_facing_fist_tone5', 'left_fist_tone5']),
  EmojiEntry('🇸🇳', ['flag_sn', 'sn']),
  EmojiEntry('🇷🇸', ['flag_rs', 'rs']),
  EmojiEntry('🇸🇨', ['flag_sc', 'sc']),
  EmojiEntry('🇸🇱', ['flag_sl', 'sl']),
  EmojiEntry('🇸🇬', ['flag_sg', 'sg']),
  EmojiEntry('🇸🇰', ['flag_sk', 'sk']),
  EmojiEntry('🇸🇮', ['flag_si', 'si']),
  EmojiEntry('🇸🇧', ['flag_sb', 'sb']),
  EmojiEntry('🇸🇴', ['flag_so', 'so']),
  EmojiEntry('🇿🇦', ['flag_za', 'za']),
  EmojiEntry('🇱🇰', ['flag_lk', 'lk']),
  EmojiEntry('🇸🇩', ['flag_sd', 'sd']),
  EmojiEntry('🇸🇷', ['flag_sr', 'sr']),
  EmojiEntry('🇸🇿', ['flag_sz', 'sz']),
  EmojiEntry('🇸🇪', ['flag_se', 'se']),
  EmojiEntry('🇨🇭', ['flag_ch', 'ch']),
  EmojiEntry('🇸🇾', ['flag_sy', 'sy']),
  EmojiEntry('🇹🇯', ['flag_tj', 'tj']),
  EmojiEntry('🇹🇿', ['flag_tz', 'tz']),
  EmojiEntry('🇹🇭', ['flag_th', 'th']),
  EmojiEntry('🇹🇬', ['flag_tg', 'tg']),
  EmojiEntry('🇹🇴', ['flag_to', 'to']),
  EmojiEntry('🇹🇹', ['flag_tt', 'tt']),
  EmojiEntry('🇹🇳', ['flag_tn', 'tn']),
  EmojiEntry('🇹🇷', ['flag_tr', 'tr']),
  EmojiEntry('🇹🇲', ['flag_tm', 'turkmenistan']),
  EmojiEntry('🇹🇻', ['flag_tv', 'tuvalu']),
  EmojiEntry('🇺🇬', ['flag_ug', 'ug']),
  EmojiEntry('🇺🇦', ['flag_ua', 'ua']),
  EmojiEntry('🇦🇪', ['flag_ae', 'ae']),
  EmojiEntry('🇺🇾', ['flag_uy', 'uy']),
  EmojiEntry('🇺🇿', ['flag_uz', 'uz']),
  EmojiEntry('🇻🇺', ['flag_vu', 'vu']),
  EmojiEntry('🇻🇦', ['flag_va', 'va']),
  EmojiEntry('🇻🇪', ['flag_ve', 've']),
  EmojiEntry('🇻🇳', ['flag_vn', 'vn']),
  EmojiEntry('🇪🇭', ['flag_eh', 'eh']),
  EmojiEntry('🤜🏻', ['right_facing_fist_tone1', 'right_fist_tone1']),
  EmojiEntry('🇾🇪', ['flag_ye', 'ye']),
  EmojiEntry('🇿🇲', ['flag_zm', 'zm']),
  EmojiEntry('🇿🇼', ['flag_zw', 'zw']),
  EmojiEntry('🇵🇷', ['flag_pr', 'pr']),
  EmojiEntry('🇰🇾', ['flag_ky', 'ky']),
  EmojiEntry('🇧🇲', ['flag_bm', 'bm']),
  EmojiEntry('🇵🇫', ['flag_pf', 'pf']),
  EmojiEntry('🇵🇸', ['flag_ps', 'ps']),
  EmojiEntry('🇳🇨', ['flag_nc', 'nc']),
  EmojiEntry('🤜🏼', ['right_facing_fist_tone2', 'right_fist_tone2']),
  EmojiEntry('🇸🇭', ['flag_sh', 'sh']),
  EmojiEntry('🇦🇼', ['flag_aw', 'aw']),
  EmojiEntry('🇻🇮', ['flag_vi', 'vi']),
  EmojiEntry('🇭🇰', ['flag_hk', 'hk']),
  EmojiEntry('🇦🇨', ['flag_ac', 'ac']),
  EmojiEntry('🇲🇸', ['flag_ms', 'ms']),
  EmojiEntry('🇬🇺', ['flag_gu', 'gu']),
  EmojiEntry('🇬🇱', ['flag_gl', 'gl']),
  EmojiEntry('🇳🇺', ['flag_nu', 'nu']),
  EmojiEntry('🇼🇫', ['flag_wf', 'wf']),
  EmojiEntry('🇲🇴', ['flag_mo', 'mo']),
  EmojiEntry('🤜🏽', ['right_facing_fist_tone3', 'right_fist_tone3']),
  EmojiEntry('🇫🇴', ['flag_fo', 'fo']),
  EmojiEntry('🇫🇰', ['flag_fk', 'fk']),
  EmojiEntry('🇯🇪', ['flag_je', 'je']),
  EmojiEntry('🇦🇮', ['flag_ai', 'ai']),
  EmojiEntry('🇬🇮', ['flag_gi', 'gi']),
  EmojiEntry('🎞️', ['film_frames']),
  EmojiEntry('🎟️', ['tickets', 'admission_tickets']),
  EmojiEntry('🏅', ['medal', 'sports_medal']),
  EmojiEntry('🏋️', ['person_lifting_weights', 'lifter', 'weight_lifter']),
  EmojiEntry('🏌️', ['person_golfing', 'golfer']),
  EmojiEntry('🏍️', ['motorcycle', 'racing_motorcycle']),
  EmojiEntry('🏎️', ['race_car', 'racing_car']),
  EmojiEntry('🎖️', ['military_medal']),
  EmojiEntry('🎗️', ['reminder_ribbon']),
  EmojiEntry('🌶️', ['hot_pepper']),
  EmojiEntry('🤜🏾', ['right_facing_fist_tone4', 'right_fist_tone4']),
  EmojiEntry('🌧️', ['cloud_rain', 'cloud_with_rain']),
  EmojiEntry('🌨️', ['cloud_snow', 'cloud_with_snow']),
  EmojiEntry('🌩️', ['cloud_lightning', 'cloud_with_lightning']),
  EmojiEntry('🌪️', ['cloud_tornado', 'cloud_with_tornado']),
  EmojiEntry('🌫️', ['fog']),
  EmojiEntry('🌬️', ['wind_blowing_face']),
  EmojiEntry('🐿️', ['chipmunk']),
  EmojiEntry('🕷️', ['spider']),
  EmojiEntry('🕸️', ['spider_web']),
  EmojiEntry('🌡️', ['thermometer']),
  EmojiEntry('🎙️', ['microphone2', 'studio_microphone']),
  EmojiEntry('🎚️', ['level_slider']),
  EmojiEntry('🎛️', ['control_knobs']),
  EmojiEntry('🏳️', ['flag_white', 'waving_white_flag']),
  EmojiEntry('🏴', ['flag_black', 'waving_black_flag']),
  EmojiEntry('🏵️', ['rosette']),
  EmojiEntry('🏷️', ['label']),
  EmojiEntry('📸', ['camera_with_flash']),
  EmojiEntry('📽️', ['projector', 'film_projector']),
  EmojiEntry('✝️', ['cross', 'latin_cross']),
  EmojiEntry('🕉️', ['om_symbol']),
  EmojiEntry('🕊️', ['dove', 'dove_of_peace']),
  EmojiEntry('🕯️', ['candle']),
  EmojiEntry('🕰️', ['clock', 'mantlepiece_clock']),
  EmojiEntry('🕳️', ['hole']),
  EmojiEntry('🕶️', ['dark_sunglasses']),
  EmojiEntry('🕹️', ['joystick']),
  EmojiEntry('🖇️', ['paperclips', 'linked_paperclips']),
  EmojiEntry('🖊️', ['pen_ballpoint', 'lower_left_ballpoint_pen']),
  EmojiEntry('🖋️', ['pen_fountain', 'lower_left_fountain_pen']),
  EmojiEntry('🖌️', ['paintbrush', 'lower_left_paintbrush']),
  EmojiEntry('🖍️', ['crayon', 'lower_left_crayon']),
  EmojiEntry('🖥️', ['desktop', 'desktop_computer']),
  EmojiEntry('🖨️', ['printer']),
  EmojiEntry('🤜🏿', ['right_facing_fist_tone5', 'right_fist_tone5']),
  EmojiEntry('⌨️', ['keyboard']),
  EmojiEntry('🖲️', ['trackball']),
  EmojiEntry('🤚🏻', ['raised_back_of_hand_tone1', 'back_of_hand_tone1']),
  EmojiEntry('🖼️', ['frame_photo', 'frame_with_picture']),
  EmojiEntry('🗂️', ['dividers', 'card_index_dividers']),
  EmojiEntry('🗃️', ['card_box', 'card_file_box']),
  EmojiEntry('🗄️', ['file_cabinet']),
  EmojiEntry('🗑️', ['wastebasket']),
  EmojiEntry('🗒️', ['notepad_spiral', 'spiral_note_pad']),
  EmojiEntry('🗓️', ['calendar_spiral', 'spiral_calendar_pad']),
  EmojiEntry('🗜️', ['compression']),
  EmojiEntry('🗝️', ['key2', 'old_key']),
  EmojiEntry('🗞️', ['newspaper2', 'rolled_up_newspaper']),
  EmojiEntry('🗡️', ['dagger', 'dagger_knife']),
  EmojiEntry('🗣️', ['speaking_head', 'speaking_head_in_silhouette']),
  EmojiEntry('🗨️', ['speech_left', 'left_speech_bubble']),
  EmojiEntry('🤚🏼', ['raised_back_of_hand_tone2', 'back_of_hand_tone2']),
  EmojiEntry('🗯️', ['anger_right', 'right_anger_bubble']),
  EmojiEntry('🤚🏽', ['raised_back_of_hand_tone3', 'back_of_hand_tone3']),
  EmojiEntry('🗳️', ['ballot_box', 'ballot_box_with_ballot']),
  EmojiEntry('🗺️', ['map', 'world_map']),
  EmojiEntry('🛌', ['sleeping_accommodation']),
  EmojiEntry('🛠️', ['tools', 'hammer_and_wrench']),
  EmojiEntry('🛡️', ['shield']),
  EmojiEntry('🛢️', ['oil', 'oil_drum']),
  EmojiEntry('🛰️', ['satellite_orbital']),
  EmojiEntry('🍽️', ['fork_knife_plate', 'fork_and_knife_with_plate']),
  EmojiEntry('👁️', ['eye']),
  EmojiEntry('🕴️', ['man_in_business_suit_levitating']),
  EmojiEntry('🕵️', ['detective', 'spy', 'sleuth_or_spy']),
  EmojiEntry('✍️', ['writing_hand']),
  EmojiEntry('🖐️', ['hand_splayed', 'raised_hand_with_fingers_splayed']),
  EmojiEntry('🖕', ['middle_finger', 'reversed_hand_with_middle_finger_extended']),
  EmojiEntry('🖖', ['vulcan', 'raised_hand_with_part_between_middle_and_ring_fingers']),
  EmojiEntry('🙁', ['slight_frown', 'slightly_frowning_face']),
  EmojiEntry('🙂', ['slight_smile', 'slightly_smiling_face']),
  EmojiEntry('🏔️', ['mountain_snow', 'snow_capped_mountain']),
  EmojiEntry('🏕️', ['camping']),
  EmojiEntry('🏖️', ['beach', 'beach_with_umbrella']),
  EmojiEntry('🏗️', ['construction_site', 'building_construction']),
  EmojiEntry('🏘️', ['homes', 'house_buildings']),
  EmojiEntry('🏙️', ['cityscape']),
  EmojiEntry('🏚️', ['house_abandoned', 'derelict_house_building']),
  EmojiEntry('🏛️', ['classical_building']),
  EmojiEntry('🏜️', ['desert']),
  EmojiEntry('🏝️', ['island', 'desert_island']),
  EmojiEntry('🏞️', ['park', 'national_park']),
  EmojiEntry('🏟️', ['stadium']),
  EmojiEntry('🛋️', ['couch', 'couch_and_lamp']),
  EmojiEntry('🤚🏾', ['raised_back_of_hand_tone4', 'back_of_hand_tone4']),
  EmojiEntry('🛍️', ['shopping_bags']),
  EmojiEntry('🛎️', ['bellhop', 'bellhop_bell']),
  EmojiEntry('🛏️', ['bed']),
  EmojiEntry('🛣️', ['motorway']),
  EmojiEntry('🛤️', ['railway_track', 'railroad_track']),
  EmojiEntry('🛥️', ['motorboat']),
  EmojiEntry('🛩️', ['airplane_small', 'small_airplane']),
  EmojiEntry('🛫', ['airplane_departure']),
  EmojiEntry('🛬', ['airplane_arriving']),
  EmojiEntry('🛳️', ['cruise_ship', 'passenger_ship']),
  EmojiEntry('👶🏻', ['baby_tone1']),
  EmojiEntry('👶🏼', ['baby_tone2']),
  EmojiEntry('👶🏽', ['baby_tone3']),
  EmojiEntry('👶🏾', ['baby_tone4']),
  EmojiEntry('👶🏿', ['baby_tone5']),
  EmojiEntry('👦🏻', ['boy_tone1']),
  EmojiEntry('👦🏼', ['boy_tone2']),
  EmojiEntry('👦🏽', ['boy_tone3']),
  EmojiEntry('👦🏾', ['boy_tone4']),
  EmojiEntry('👦🏿', ['boy_tone5']),
  EmojiEntry('👧🏻', ['girl_tone1']),
  EmojiEntry('👧🏼', ['girl_tone2']),
  EmojiEntry('👧🏽', ['girl_tone3']),
  EmojiEntry('👧🏾', ['girl_tone4']),
  EmojiEntry('👧🏿', ['girl_tone5']),
  EmojiEntry('👨🏻', ['man_tone1']),
  EmojiEntry('👨🏼', ['man_tone2']),
  EmojiEntry('👨🏽', ['man_tone3']),
  EmojiEntry('👨🏾', ['man_tone4']),
  EmojiEntry('👨🏿', ['man_tone5']),
  EmojiEntry('👩🏻', ['woman_tone1']),
  EmojiEntry('👩🏼', ['woman_tone2']),
  EmojiEntry('👩🏽', ['woman_tone3']),
  EmojiEntry('👩🏾', ['woman_tone4']),
  EmojiEntry('👩🏿', ['woman_tone5']),
  EmojiEntry('👰🏻', ['bride_with_veil_tone1']),
  EmojiEntry('👰🏼', ['bride_with_veil_tone2']),
  EmojiEntry('🤚🏿', ['raised_back_of_hand_tone5', 'back_of_hand_tone5']),
  EmojiEntry('👰🏽', ['bride_with_veil_tone3']),
  EmojiEntry('👰🏾', ['bride_with_veil_tone4']),
  EmojiEntry('👰🏿', ['bride_with_veil_tone5']),
  EmojiEntry('👱🏻', ['blond_haired_person_tone1', 'person_with_blond_hair_tone1']),
  EmojiEntry('👱🏼', ['blond_haired_person_tone2', 'person_with_blond_hair_tone2']),
  EmojiEntry('👱🏽', ['blond_haired_person_tone3', 'person_with_blond_hair_tone3']),
  EmojiEntry('👱🏾', ['blond_haired_person_tone4', 'person_with_blond_hair_tone4']),
  EmojiEntry('👱🏿', ['blond_haired_person_tone5', 'person_with_blond_hair_tone5']),
  EmojiEntry('👲🏻', ['man_with_chinese_cap_tone1', 'man_with_gua_pi_mao_tone1']),
  EmojiEntry('👲🏼', ['man_with_chinese_cap_tone2', 'man_with_gua_pi_mao_tone2']),
  EmojiEntry('👲🏽', ['man_with_chinese_cap_tone3', 'man_with_gua_pi_mao_tone3']),
  EmojiEntry('👲🏾', ['man_with_chinese_cap_tone4', 'man_with_gua_pi_mao_tone4']),
  EmojiEntry('👲🏿', ['man_with_chinese_cap_tone5', 'man_with_gua_pi_mao_tone5']),
  EmojiEntry('👳🏻', ['person_wearing_turban_tone1', 'man_with_turban_tone1']),
  EmojiEntry('👳🏼', ['person_wearing_turban_tone2', 'man_with_turban_tone2']),
  EmojiEntry('👳🏽', ['person_wearing_turban_tone3', 'man_with_turban_tone3']),
  EmojiEntry('👳🏾', ['person_wearing_turban_tone4', 'man_with_turban_tone4']),
  EmojiEntry('👳🏿', ['person_wearing_turban_tone5', 'man_with_turban_tone5']),
  EmojiEntry('👴🏻', ['older_man_tone1']),
  EmojiEntry('👴🏼', ['older_man_tone2']),
  EmojiEntry('👴🏽', ['older_man_tone3']),
  EmojiEntry('👴🏾', ['older_man_tone4']),
  EmojiEntry('👴🏿', ['older_man_tone5']),
  EmojiEntry('👵🏻', ['older_woman_tone1', 'grandma_tone1']),
  EmojiEntry('👵🏼', ['older_woman_tone2', 'grandma_tone2']),
  EmojiEntry('👵🏽', ['older_woman_tone3', 'grandma_tone3']),
  EmojiEntry('👵🏾', ['older_woman_tone4', 'grandma_tone4']),
  EmojiEntry('👵🏿', ['older_woman_tone5', 'grandma_tone5']),
  EmojiEntry('👮🏻', ['police_officer_tone1', 'cop_tone1']),
  EmojiEntry('👮🏼', ['police_officer_tone2', 'cop_tone2']),
  EmojiEntry('👮🏽', ['police_officer_tone3', 'cop_tone3']),
  EmojiEntry('👮🏾', ['police_officer_tone4', 'cop_tone4']),
  EmojiEntry('👮🏿', ['police_officer_tone5', 'cop_tone5']),
  EmojiEntry('👷🏻', ['construction_worker_tone1']),
  EmojiEntry('👷🏼', ['construction_worker_tone2']),
  EmojiEntry('👷🏽', ['construction_worker_tone3']),
  EmojiEntry('👷🏾', ['construction_worker_tone4']),
  EmojiEntry('👷🏿', ['construction_worker_tone5']),
  EmojiEntry('👸🏻', ['princess_tone1']),
  EmojiEntry('👸🏼', ['princess_tone2']),
  EmojiEntry('👸🏽', ['princess_tone3']),
  EmojiEntry('👸🏾', ['princess_tone4']),
  EmojiEntry('🤸🏻', ['person_doing_cartwheel_tone1', 'cartwheel_tone1']),
  EmojiEntry('👸🏿', ['princess_tone5']),
  EmojiEntry('💂🏻', ['guard_tone1', 'guardsman_tone1']),
  EmojiEntry('💂🏼', ['guard_tone2', 'guardsman_tone2']),
  EmojiEntry('🤸🏼', ['person_doing_cartwheel_tone2', 'cartwheel_tone2']),
  EmojiEntry('💂🏽', ['guard_tone3', 'guardsman_tone3']),
  EmojiEntry('💂🏾', ['guard_tone4', 'guardsman_tone4']),
  EmojiEntry('💂🏿', ['guard_tone5', 'guardsman_tone5']),
  EmojiEntry('🤸🏽', ['person_doing_cartwheel_tone3', 'cartwheel_tone3']),
  EmojiEntry('👼🏻', ['angel_tone1']),
  EmojiEntry('👼🏼', ['angel_tone2']),
  EmojiEntry('👼🏽', ['angel_tone3']),
  EmojiEntry('👼🏾', ['angel_tone4']),
  EmojiEntry('👼🏿', ['angel_tone5']),
  EmojiEntry('🙇🏻', ['person_bowing_tone1', 'bow_tone1']),
  EmojiEntry('🙇🏼', ['person_bowing_tone2', 'bow_tone2']),
  EmojiEntry('🙇🏽', ['person_bowing_tone3', 'bow_tone3']),
  EmojiEntry('🙇🏾', ['person_bowing_tone4', 'bow_tone4']),
  EmojiEntry('🙇🏿', ['person_bowing_tone5', 'bow_tone5']),
  EmojiEntry('💁🏻', ['person_tipping_hand_tone1', 'information_desk_person_tone1']),
  EmojiEntry('💁🏼', ['person_tipping_hand_tone2', 'information_desk_person_tone2']),
  EmojiEntry('💁🏽', ['person_tipping_hand_tone3', 'information_desk_person_tone3']),
  EmojiEntry('🤸🏾', ['person_doing_cartwheel_tone4', 'cartwheel_tone4']),
  EmojiEntry('💁🏾', ['person_tipping_hand_tone4', 'information_desk_person_tone4']),
  EmojiEntry('💁🏿', ['person_tipping_hand_tone5', 'information_desk_person_tone5']),
  EmojiEntry('🙅🏻', ['person_gesturing_no_tone1', 'no_good_tone1']),
  EmojiEntry('🤸🏿', ['person_doing_cartwheel_tone5', 'cartwheel_tone5']),
  EmojiEntry('🙅🏼', ['person_gesturing_no_tone2', 'no_good_tone2']),
  EmojiEntry('🙅🏽', ['person_gesturing_no_tone3', 'no_good_tone3']),
  EmojiEntry('🙅🏾', ['person_gesturing_no_tone4', 'no_good_tone4']),
  EmojiEntry('🙅🏿', ['person_gesturing_no_tone5', 'no_good_tone5']),
  EmojiEntry('🙆🏻', ['person_gesturing_ok_tone1', 'ok_woman_tone1']),
  EmojiEntry('🙆🏼', ['person_gesturing_ok_tone2', 'ok_woman_tone2']),
  EmojiEntry('🙆🏽', ['person_gesturing_ok_tone3', 'ok_woman_tone3']),
  EmojiEntry('🙆🏾', ['person_gesturing_ok_tone4', 'ok_woman_tone4']),
  EmojiEntry('🙆🏿', ['person_gesturing_ok_tone5', 'ok_woman_tone5']),
  EmojiEntry('🙋🏻', ['person_raising_hand_tone1', 'raising_hand_tone1']),
  EmojiEntry('🙋🏼', ['person_raising_hand_tone2', 'raising_hand_tone2']),
  EmojiEntry('🙋🏽', ['person_raising_hand_tone3', 'raising_hand_tone3']),
  EmojiEntry('🙋🏾', ['person_raising_hand_tone4', 'raising_hand_tone4']),
  EmojiEntry('🙋🏿', ['person_raising_hand_tone5', 'raising_hand_tone5']),
  EmojiEntry('🙎🏻', ['person_pouting_tone1', 'person_with_pouting_face_tone1']),
  EmojiEntry('🙎🏼', ['person_pouting_tone2', 'person_with_pouting_face_tone2']),
  EmojiEntry('🙎🏽', ['person_pouting_tone3', 'person_with_pouting_face_tone3']),
  EmojiEntry('🙎🏾', ['person_pouting_tone4', 'person_with_pouting_face_tone4']),
  EmojiEntry('🙎🏿', ['person_pouting_tone5', 'person_with_pouting_face_tone5']),
  EmojiEntry('🙍🏻', ['person_frowning_tone1']),
  EmojiEntry('🙍🏼', ['person_frowning_tone2']),
  EmojiEntry('🙍🏽', ['person_frowning_tone3']),
  EmojiEntry('🙍🏾', ['person_frowning_tone4']),
  EmojiEntry('🙍🏿', ['person_frowning_tone5']),
  EmojiEntry('💆🏻', ['person_getting_massage_tone1', 'massage_tone1']),
  EmojiEntry('💆🏼', ['person_getting_massage_tone2', 'massage_tone2']),
  EmojiEntry('💆🏽', ['person_getting_massage_tone3', 'massage_tone3']),
  EmojiEntry('💆🏾', ['person_getting_massage_tone4', 'massage_tone4']),
  EmojiEntry('💆🏿', ['person_getting_massage_tone5', 'massage_tone5']),
  EmojiEntry('💇🏻', ['person_getting_haircut_tone1', 'haircut_tone1']),
  EmojiEntry('💇🏼', ['person_getting_haircut_tone2', 'haircut_tone2']),
  EmojiEntry('💇🏽', ['person_getting_haircut_tone3', 'haircut_tone3']),
  EmojiEntry('💇🏾', ['person_getting_haircut_tone4', 'haircut_tone4']),
  EmojiEntry('💇🏿', ['person_getting_haircut_tone5', 'haircut_tone5']),
  EmojiEntry('🙌🏻', ['raised_hands_tone1']),
  EmojiEntry('🙌🏼', ['raised_hands_tone2']),
  EmojiEntry('🙌🏽', ['raised_hands_tone3']),
  EmojiEntry('🙌🏾', ['raised_hands_tone4']),
  EmojiEntry('🙌🏿', ['raised_hands_tone5']),
  EmojiEntry('👏🏻', ['clap_tone1']),
  EmojiEntry('👏🏼', ['clap_tone2']),
  EmojiEntry('👏🏽', ['clap_tone3']),
  EmojiEntry('🤽🏻', ['person_playing_water_polo_tone1', 'water_polo_tone1']),
  EmojiEntry('👏🏾', ['clap_tone4']),
  EmojiEntry('👏🏿', ['clap_tone5']),
  EmojiEntry('🤽🏼', ['person_playing_water_polo_tone2', 'water_polo_tone2']),
  EmojiEntry('👂🏻', ['ear_tone1']),
  EmojiEntry('👂🏼', ['ear_tone2']),
  EmojiEntry('👂🏽', ['ear_tone3']),
  EmojiEntry('👂🏾', ['ear_tone4']),
  EmojiEntry('👂🏿', ['ear_tone5']),
  EmojiEntry('👃🏻', ['nose_tone1']),
  EmojiEntry('👃🏼', ['nose_tone2']),
  EmojiEntry('👃🏽', ['nose_tone3']),
  EmojiEntry('👃🏾', ['nose_tone4']),
  EmojiEntry('👃🏿', ['nose_tone5']),
  EmojiEntry('💅🏻', ['nail_care_tone1']),
  EmojiEntry('💅🏼', ['nail_care_tone2']),
  EmojiEntry('💅🏽', ['nail_care_tone3']),
  EmojiEntry('💅🏾', ['nail_care_tone4']),
  EmojiEntry('💅🏿', ['nail_care_tone5']),
  EmojiEntry('👋🏻', ['wave_tone1']),
  EmojiEntry('👋🏼', ['wave_tone2']),
  EmojiEntry('👋🏽', ['wave_tone3']),
  EmojiEntry('👋🏾', ['wave_tone4']),
  EmojiEntry('👋🏿', ['wave_tone5']),
  EmojiEntry('👍🏻', ['thumbsup_tone1', '+1_tone1', 'thumbup_tone1']),
  EmojiEntry('👍🏼', ['thumbsup_tone2', '+1_tone2', 'thumbup_tone2']),
  EmojiEntry('👍🏽', ['thumbsup_tone3', '+1_tone3', 'thumbup_tone3']),
  EmojiEntry('👍🏾', ['thumbsup_tone4', '+1_tone4', 'thumbup_tone4']),
  EmojiEntry('👍🏿', ['thumbsup_tone5', '+1_tone5', 'thumbup_tone5']),
  EmojiEntry('👎🏻', ['thumbsdown_tone1', '-1_tone1', 'thumbdown_tone1']),
  EmojiEntry('👎🏼', ['thumbsdown_tone2', '-1_tone2', 'thumbdown_tone2']),
  EmojiEntry('👎🏽', ['thumbsdown_tone3', '-1_tone3', 'thumbdown_tone3']),
  EmojiEntry('👎🏾', ['thumbsdown_tone4', '-1_tone4', 'thumbdown_tone4']),
  EmojiEntry('👎🏿', ['thumbsdown_tone5', '-1_tone5', 'thumbdown_tone5']),
  EmojiEntry('☝🏻', ['point_up_tone1']),
  EmojiEntry('☝🏼', ['point_up_tone2']),
  EmojiEntry('☝🏽', ['point_up_tone3']),
  EmojiEntry('☝🏾', ['point_up_tone4']),
  EmojiEntry('☝🏿', ['point_up_tone5']),
  EmojiEntry('👆🏻', ['point_up_2_tone1']),
  EmojiEntry('👆🏼', ['point_up_2_tone2']),
  EmojiEntry('👆🏽', ['point_up_2_tone3']),
  EmojiEntry('👆🏾', ['point_up_2_tone4']),
  EmojiEntry('👆🏿', ['point_up_2_tone5']),
  EmojiEntry('👇🏻', ['point_down_tone1']),
  EmojiEntry('👇🏼', ['point_down_tone2']),
  EmojiEntry('👇🏽', ['point_down_tone3']),
  EmojiEntry('👇🏾', ['point_down_tone4']),
  EmojiEntry('👇🏿', ['point_down_tone5']),
  EmojiEntry('👈🏻', ['point_left_tone1']),
  EmojiEntry('👈🏼', ['point_left_tone2']),
  EmojiEntry('👈🏽', ['point_left_tone3']),
  EmojiEntry('👈🏾', ['point_left_tone4']),
  EmojiEntry('👈🏿', ['point_left_tone5']),
  EmojiEntry('👉🏻', ['point_right_tone1']),
  EmojiEntry('👉🏼', ['point_right_tone2']),
  EmojiEntry('👉🏽', ['point_right_tone3']),
  EmojiEntry('👉🏾', ['point_right_tone4']),
  EmojiEntry('👉🏿', ['point_right_tone5']),
  EmojiEntry('👌🏻', ['ok_hand_tone1']),
  EmojiEntry('👌🏼', ['ok_hand_tone2']),
  EmojiEntry('🤽🏽', ['person_playing_water_polo_tone3', 'water_polo_tone3']),
  EmojiEntry('👌🏽', ['ok_hand_tone3']),
  EmojiEntry('👌🏾', ['ok_hand_tone4']),
  EmojiEntry('🤽🏾', ['person_playing_water_polo_tone4', 'water_polo_tone4']),
  EmojiEntry('👌🏿', ['ok_hand_tone5']),
  EmojiEntry('✌🏻', ['v_tone1']),
  EmojiEntry('✌🏼', ['v_tone2']),
  EmojiEntry('✌🏽', ['v_tone3']),
  EmojiEntry('✌🏾', ['v_tone4']),
  EmojiEntry('✌🏿', ['v_tone5']),
  EmojiEntry('👊🏻', ['punch_tone1']),
  EmojiEntry('👊🏼', ['punch_tone2']),
  EmojiEntry('👊🏽', ['punch_tone3']),
  EmojiEntry('👊🏾', ['punch_tone4']),
  EmojiEntry('👊🏿', ['punch_tone5']),
  EmojiEntry('✊🏻', ['fist_tone1']),
  EmojiEntry('✊🏼', ['fist_tone2']),
  EmojiEntry('✊🏽', ['fist_tone3']),
  EmojiEntry('✊🏾', ['fist_tone4']),
  EmojiEntry('✊🏿', ['fist_tone5']),
  EmojiEntry('✋🏻', ['raised_hand_tone1']),
  EmojiEntry('✋🏼', ['raised_hand_tone2']),
  EmojiEntry('✋🏽', ['raised_hand_tone3']),
  EmojiEntry('✋🏾', ['raised_hand_tone4']),
  EmojiEntry('✋🏿', ['raised_hand_tone5']),
  EmojiEntry('💪🏻', ['muscle_tone1']),
  EmojiEntry('💪🏼', ['muscle_tone2']),
  EmojiEntry('💪🏽', ['muscle_tone3']),
  EmojiEntry('💪🏾', ['muscle_tone4']),
  EmojiEntry('💪🏿', ['muscle_tone5']),
  EmojiEntry('👐🏻', ['open_hands_tone1']),
  EmojiEntry('👐🏼', ['open_hands_tone2']),
  EmojiEntry('👐🏽', ['open_hands_tone3']),
  EmojiEntry('👐🏾', ['open_hands_tone4']),
  EmojiEntry('👐🏿', ['open_hands_tone5']),
  EmojiEntry('🙏🏻', ['pray_tone1']),
  EmojiEntry('🤽🏿', ['person_playing_water_polo_tone5', 'water_polo_tone5']),
  EmojiEntry('🙏🏼', ['pray_tone2']),
  EmojiEntry('🙏🏽', ['pray_tone3']),
  EmojiEntry('🤾🏻', ['person_playing_handball_tone1', 'handball_tone1']),
  EmojiEntry('🙏🏾', ['pray_tone4']),
  EmojiEntry('🙏🏿', ['pray_tone5']),
  EmojiEntry('🤾🏼', ['person_playing_handball_tone2', 'handball_tone2']),
  EmojiEntry('🏃🏻', ['person_running_tone1', 'runner_tone1']),
  EmojiEntry('🏃🏼', ['person_running_tone2', 'runner_tone2']),
  EmojiEntry('🏃🏽', ['person_running_tone3', 'runner_tone3']),
  EmojiEntry('🏃🏾', ['person_running_tone4', 'runner_tone4']),
  EmojiEntry('🤾🏽', ['person_playing_handball_tone3', 'handball_tone3']),
  EmojiEntry('🏃🏿', ['person_running_tone5', 'runner_tone5']),
  EmojiEntry('🚶🏻', ['person_walking_tone1', 'walking_tone1']),
  EmojiEntry('🚶🏼', ['person_walking_tone2', 'walking_tone2']),
  EmojiEntry('🚶🏽', ['person_walking_tone3', 'walking_tone3']),
  EmojiEntry('🚶🏾', ['person_walking_tone4', 'walking_tone4']),
  EmojiEntry('🚶🏿', ['person_walking_tone5', 'walking_tone5']),
  EmojiEntry('💃🏻', ['dancer_tone1']),
  EmojiEntry('🤾🏾', ['person_playing_handball_tone4', 'handball_tone4']),
  EmojiEntry('💃🏼', ['dancer_tone2']),
  EmojiEntry('💃🏽', ['dancer_tone3']),
  EmojiEntry('🤾🏿', ['person_playing_handball_tone5', 'handball_tone5']),
  EmojiEntry('💃🏾', ['dancer_tone4']),
  EmojiEntry('💃🏿', ['dancer_tone5']),
  EmojiEntry('🤹🏻', ['person_juggling_tone1', 'juggling_tone1', 'juggler_tone1']),
  EmojiEntry('🚣🏻', ['person_rowing_boat_tone1', 'rowboat_tone1']),
  EmojiEntry('🚣🏼', ['person_rowing_boat_tone2', 'rowboat_tone2']),
  EmojiEntry('🚣🏽', ['person_rowing_boat_tone3', 'rowboat_tone3']),
  EmojiEntry('🚣🏾', ['person_rowing_boat_tone4', 'rowboat_tone4']),
  EmojiEntry('🚣🏿', ['person_rowing_boat_tone5', 'rowboat_tone5']),
  EmojiEntry('🏊🏻', ['person_swimming_tone1', 'swimmer_tone1']),
  EmojiEntry('🏊🏼', ['person_swimming_tone2', 'swimmer_tone2']),
  EmojiEntry('🤹🏼', ['person_juggling_tone2', 'juggling_tone2', 'juggler_tone2']),
  EmojiEntry('🏊🏽', ['person_swimming_tone3', 'swimmer_tone3']),
  EmojiEntry('🏊🏾', ['person_swimming_tone4', 'swimmer_tone4']),
  EmojiEntry('🏊🏿', ['person_swimming_tone5', 'swimmer_tone5']),
  EmojiEntry('🤹🏽', ['person_juggling_tone3', 'juggling_tone3', 'juggler_tone3']),
  EmojiEntry('🏄🏻', ['person_surfing_tone1', 'surfer_tone1']),
  EmojiEntry('🏄🏼', ['person_surfing_tone2', 'surfer_tone2']),
  EmojiEntry('🏄🏽', ['person_surfing_tone3', 'surfer_tone3']),
  EmojiEntry('🏄🏾', ['person_surfing_tone4', 'surfer_tone4']),
  EmojiEntry('🏄🏿', ['person_surfing_tone5', 'surfer_tone5']),
  EmojiEntry('🛀🏻', ['bath_tone1']),
  EmojiEntry('🛀🏼', ['bath_tone2']),
  EmojiEntry('🤹🏾', ['person_juggling_tone4', 'juggling_tone4', 'juggler_tone4']),
  EmojiEntry('🛀🏽', ['bath_tone3']),
  EmojiEntry('🛀🏾', ['bath_tone4']),
  EmojiEntry('🛀🏿', ['bath_tone5']),
  EmojiEntry('🤹🏿', ['person_juggling_tone5', 'juggling_tone5', 'juggler_tone5']),
  EmojiEntry('🚴🏻', ['person_biking_tone1', 'bicyclist_tone1']),
  EmojiEntry('🚴🏼', ['person_biking_tone2', 'bicyclist_tone2']),
  EmojiEntry('🚴🏽', ['person_biking_tone3', 'bicyclist_tone3']),
  EmojiEntry('🏳️‍🌈', ['rainbow_flag', 'gay_pride_flag']),
  EmojiEntry('🚴🏾', ['person_biking_tone4', 'bicyclist_tone4']),
  EmojiEntry('🚴🏿', ['person_biking_tone5', 'bicyclist_tone5']),
  EmojiEntry('🚵🏻', ['person_mountain_biking_tone1', 'mountain_bicyclist_tone1']),
  EmojiEntry('🚵🏼', ['person_mountain_biking_tone2', 'mountain_bicyclist_tone2']),
  EmojiEntry('🚵🏽', ['person_mountain_biking_tone3', 'mountain_bicyclist_tone3']),
  EmojiEntry('🚵🏾', ['person_mountain_biking_tone4', 'mountain_bicyclist_tone4']),
  EmojiEntry('🚵🏿', ['person_mountain_biking_tone5', 'mountain_bicyclist_tone5']),
  EmojiEntry('🏇🏻', ['horse_racing_tone1']),
  EmojiEntry('🏇🏼', ['horse_racing_tone2']),
  EmojiEntry('🏇🏽', ['horse_racing_tone3']),
  EmojiEntry('🏇🏾', ['horse_racing_tone4']),
  EmojiEntry('🏇🏿', ['horse_racing_tone5']),
  EmojiEntry('✍🏻', ['writing_hand_tone1']),
  EmojiEntry('✍🏼', ['writing_hand_tone2']),
  EmojiEntry('✍🏽', ['writing_hand_tone3']),
  EmojiEntry('✍🏾', ['writing_hand_tone4']),
  EmojiEntry('✍🏿', ['writing_hand_tone5']),
  EmojiEntry('🖐🏻', ['hand_splayed_tone1', 'raised_hand_with_fingers_splayed_tone1']),
  EmojiEntry('🖐🏼', ['hand_splayed_tone2', 'raised_hand_with_fingers_splayed_tone2']),
  EmojiEntry('🖐🏽', ['hand_splayed_tone3', 'raised_hand_with_fingers_splayed_tone3']),
  EmojiEntry('🖐🏾', ['hand_splayed_tone4', 'raised_hand_with_fingers_splayed_tone4']),
  EmojiEntry('🖐🏿', ['hand_splayed_tone5', 'raised_hand_with_fingers_splayed_tone5']),
  EmojiEntry('🖕🏻', ['middle_finger_tone1', 'reversed_hand_with_middle_finger_extended_tone1']),
  EmojiEntry('🖕🏼', ['middle_finger_tone2', 'reversed_hand_with_middle_finger_extended_tone2']),
  EmojiEntry('🖕🏽', ['middle_finger_tone3', 'reversed_hand_with_middle_finger_extended_tone3']),
  EmojiEntry('🖕🏾', ['middle_finger_tone4', 'reversed_hand_with_middle_finger_extended_tone4']),
  EmojiEntry('🖕🏿', ['middle_finger_tone5', 'reversed_hand_with_middle_finger_extended_tone5']),
  EmojiEntry('🖖🏻', ['vulcan_tone1', 'raised_hand_with_part_between_middle_and_ring_fingers_tone1']),
  EmojiEntry('🖖🏼', ['vulcan_tone2', 'raised_hand_with_part_between_middle_and_ring_fingers_tone2']),
  EmojiEntry('🖖🏽', ['vulcan_tone3', 'raised_hand_with_part_between_middle_and_ring_fingers_tone3']),
  EmojiEntry('🖖🏾', ['vulcan_tone4', 'raised_hand_with_part_between_middle_and_ring_fingers_tone4']),
  EmojiEntry('🖖🏿', ['vulcan_tone5', 'raised_hand_with_part_between_middle_and_ring_fingers_tone5']),
  EmojiEntry('👨‍👨‍👦', ['family_mmb']),
  EmojiEntry('👨‍👨‍👦‍👦', ['family_mmbb']),
  EmojiEntry('👨‍👨‍👧', ['family_mmg']),
  EmojiEntry('👨‍👨‍👧‍👦', ['family_mmgb']),
  EmojiEntry('👨‍👨‍👧‍👧', ['family_mmgg']),
  EmojiEntry('👨‍👩‍👦‍👦', ['family_mwbb']),
  EmojiEntry('👨‍👩‍👧', ['family_mwg']),
  EmojiEntry('👨‍👩‍👧‍👦', ['family_mwgb']),
  EmojiEntry('👨‍👩‍👧‍👧', ['family_mwgg']),
  EmojiEntry('👩‍👩‍👦', ['family_wwb']),
  EmojiEntry('👩‍👩‍👦‍👦', ['family_wwbb']),
  EmojiEntry('👩‍👩‍👧', ['family_wwg']),
  EmojiEntry('👩‍👩‍👧‍👦', ['family_wwgb']),
  EmojiEntry('👩‍👩‍👧‍👧', ['family_wwgg']),
  EmojiEntry('👩‍❤️‍👩', ['couple_ww', 'couple_with_heart_ww']),
  EmojiEntry('👨‍❤️‍👨', ['couple_mm', 'couple_with_heart_mm']),
  EmojiEntry('👩‍❤️‍💋‍👩', ['kiss_ww', 'couplekiss_ww']),
  EmojiEntry('👨‍❤️‍💋‍👨', ['kiss_mm', 'couplekiss_mm']),
  EmojiEntry('🏻', ['tone1']),
  EmojiEntry('🏼', ['tone2']),
  EmojiEntry('🏽', ['tone3']),
  EmojiEntry('🏾', ['tone4']),
  EmojiEntry('🏿', ['tone5']),
  EmojiEntry('*️⃣', ['asterisk', 'keycap_asterisk']),
  EmojiEntry('⏏️', ['eject', 'eject_symbol']),
  EmojiEntry('⏭️', ['track_next', 'next_track']),
  EmojiEntry('⏮️', ['track_previous', 'previous_track']),
  EmojiEntry('⏯️', ['play_pause']),
  EmojiEntry('👁️‍🗨️', ['eye_in_speech_bubble']),
  EmojiEntry('⏱️', ['stopwatch']),
  EmojiEntry('⏲️', ['timer', 'timer_clock']),
  EmojiEntry('⏸️', ['pause_button', 'double_vertical_bar']),
  EmojiEntry('⏹️', ['stop_button']),
  EmojiEntry('⏺️', ['record_button']),
  EmojiEntry('☂️', ['umbrella2']),
  EmojiEntry('☃️', ['snowman2']),
  EmojiEntry('☄️', ['comet']),
  EmojiEntry('☘️', ['shamrock']),
  EmojiEntry('☠️', ['skull_crossbones', 'skull_and_crossbones']),
  EmojiEntry('☢️', ['radioactive', 'radioactive_sign']),
  EmojiEntry('☣️', ['biohazard', 'biohazard_sign']),
  EmojiEntry('☦️', ['orthodox_cross']),
  EmojiEntry('☪️', ['star_and_crescent']),
  EmojiEntry('☮️', ['peace', 'peace_symbol']),
  EmojiEntry('☯️', ['yin_yang']),
  EmojiEntry('☸️', ['wheel_of_dharma']),
  EmojiEntry('☹️', ['frowning2', 'white_frowning_face']),
  EmojiEntry('⚒️', ['hammer_pick', 'hammer_and_pick']),
  EmojiEntry('⚔️', ['crossed_swords']),
  EmojiEntry('⚖️', ['scales']),
  EmojiEntry('⚗️', ['alembic']),
  EmojiEntry('⚙️', ['gear']),
  EmojiEntry('⚛️', ['atom', 'atom_symbol']),
  EmojiEntry('⚜️', ['fleur-de-lis']),
  EmojiEntry('⚰️', ['coffin']),
  EmojiEntry('⚱️', ['urn', 'funeral_urn']),
  EmojiEntry('⛈️', ['thunder_cloud_rain', 'thunder_cloud_and_rain']),
  EmojiEntry('⛏️', ['pick']),
  EmojiEntry('⛑️', ['helmet_with_cross', 'helmet_with_white_cross']),
  EmojiEntry('⛓️', ['chains']),
  EmojiEntry('⛩️', ['shinto_shrine']),
  EmojiEntry('⛰️', ['mountain']),
  EmojiEntry('⛱️', ['beach_umbrella', 'umbrella_on_ground']),
  EmojiEntry('⛴️', ['ferry']),
  EmojiEntry('⛷️', ['skier']),
  EmojiEntry('⛸️', ['ice_skate']),
  EmojiEntry('⛹️', ['person_bouncing_ball', 'basketball_player', 'person_with_ball']),
  EmojiEntry('✡️', ['star_of_david']),
  EmojiEntry('❣️', ['heart_exclamation', 'heavy_heart_exclamation_mark_ornament']),
  EmojiEntry('🌤️', ['white_sun_small_cloud', 'white_sun_with_small_cloud']),
  EmojiEntry('🌥️', ['white_sun_cloud', 'white_sun_behind_cloud']),
  EmojiEntry('🌦️', ['white_sun_rain_cloud', 'white_sun_behind_cloud_with_rain']),
  EmojiEntry('🖱️', ['mouse_three_button', 'three_button_mouse']),
  EmojiEntry('🎅🏻', ['santa_tone1']),
  EmojiEntry('🎅🏼', ['santa_tone2']),
  EmojiEntry('🎅🏽', ['santa_tone3']),
  EmojiEntry('🎅🏾', ['santa_tone4']),
  EmojiEntry('🎅🏿', ['santa_tone5']),
  EmojiEntry('🤘🏻', ['metal_tone1', 'sign_of_the_horns_tone1']),
  EmojiEntry('🤘🏼', ['metal_tone2', 'sign_of_the_horns_tone2']),
  EmojiEntry('🤘🏽', ['metal_tone3', 'sign_of_the_horns_tone3']),
  EmojiEntry('🤘🏾', ['metal_tone4', 'sign_of_the_horns_tone4']),
  EmojiEntry('🤘🏿', ['metal_tone5', 'sign_of_the_horns_tone5']),
  EmojiEntry('🏋🏻', ['person_lifting_weights_tone1', 'lifter_tone1', 'weight_lifter_tone1']),
  EmojiEntry('🏋🏼', ['person_lifting_weights_tone2', 'lifter_tone2', 'weight_lifter_tone2']),
  EmojiEntry('🏋🏽', ['person_lifting_weights_tone3', 'lifter_tone3', 'weight_lifter_tone3']),
  EmojiEntry('🏋🏾', ['person_lifting_weights_tone4', 'lifter_tone4', 'weight_lifter_tone4']),
  EmojiEntry('🏋🏿', ['person_lifting_weights_tone5', 'lifter_tone5', 'weight_lifter_tone5']),
  EmojiEntry('⛹🏻', ['person_bouncing_ball_tone1', 'basketball_player_tone1', 'person_with_ball_tone1']),
  EmojiEntry('⛹🏼', ['person_bouncing_ball_tone2', 'basketball_player_tone2', 'person_with_ball_tone2']),
  EmojiEntry('⛹🏽', ['person_bouncing_ball_tone3', 'basketball_player_tone3', 'person_with_ball_tone3']),
  EmojiEntry('⛹🏾', ['person_bouncing_ball_tone4', 'basketball_player_tone4', 'person_with_ball_tone4']),
  EmojiEntry('⛹🏿', ['person_bouncing_ball_tone5', 'basketball_player_tone5', 'person_with_ball_tone5']),
  EmojiEntry('🙃', ['upside_down', 'upside_down_face']),
  EmojiEntry('🤑', ['money_mouth', 'money_mouth_face']),
  EmojiEntry('🤓', ['nerd', 'nerd_face']),
  EmojiEntry('🤗', ['hugging', 'hugging_face']),
  EmojiEntry('🙄', ['rolling_eyes', 'face_with_rolling_eyes']),
  EmojiEntry('🤔', ['thinking', 'thinking_face']),
  EmojiEntry('🤐', ['zipper_mouth', 'zipper_mouth_face']),
  EmojiEntry('🤒', ['thermometer_face', 'face_with_thermometer']),
  EmojiEntry('🤕', ['head_bandage', 'face_with_head_bandage']),
  EmojiEntry('🤖', ['robot', 'robot_face']),
  EmojiEntry('🦁', ['lion_face', 'lion']),
  EmojiEntry('🦄', ['unicorn', 'unicorn_face']),
  EmojiEntry('🦂', ['scorpion']),
  EmojiEntry('🦀', ['crab']),
  EmojiEntry('🦃', ['turkey']),
  EmojiEntry('🧀', ['cheese', 'cheese_wedge']),
  EmojiEntry('🌭', ['hotdog', 'hot_dog']),
  EmojiEntry('🌮', ['taco']),
  EmojiEntry('🌯', ['burrito']),
  EmojiEntry('🍿', ['popcorn']),
  EmojiEntry('🍾', ['champagne', 'bottle_with_popping_cork']),
  EmojiEntry('🏹', ['bow_and_arrow', 'archery']),
  EmojiEntry('🏺', ['amphora']),
  EmojiEntry('🛐', ['place_of_worship', 'worship_symbol']),
  EmojiEntry('🕋', ['kaaba']),
  EmojiEntry('🕌', ['mosque']),
  EmojiEntry('🕍', ['synagogue']),
  EmojiEntry('🕎', ['menorah']),
  EmojiEntry('📿', ['prayer_beads']),
  EmojiEntry('🏏', ['cricket_game', 'cricket_bat_ball']),
  EmojiEntry('🏐', ['volleyball']),
  EmojiEntry('🏑', ['field_hockey']),
  EmojiEntry('🏒', ['hockey']),
  EmojiEntry('🏓', ['ping_pong', 'table_tennis']),
  EmojiEntry('🏸', ['badminton']),
  EmojiEntry('🇦🇽', ['flag_ax', 'ax']),
  EmojiEntry('🇹🇦', ['flag_ta', 'ta']),
  EmojiEntry('🇮🇴', ['flag_io', 'io']),
  EmojiEntry('🇧🇶', ['flag_bq', 'bq']),
  EmojiEntry('🇨🇽', ['flag_cx', 'cx']),
  EmojiEntry('🇨🇨', ['flag_cc', 'cc']),
  EmojiEntry('🇬🇬', ['flag_gg', 'gg']),
  EmojiEntry('🇮🇲', ['flag_im', 'im']),
  EmojiEntry('🇾🇹', ['flag_yt', 'yt']),
  EmojiEntry('🇳🇫', ['flag_nf', 'nf']),
  EmojiEntry('🇵🇳', ['flag_pn', 'pn']),
  EmojiEntry('🇧🇱', ['flag_bl', 'bl']),
  EmojiEntry('🇵🇲', ['flag_pm', 'pm']),
  EmojiEntry('🇬🇸', ['flag_gs', 'gs']),
  EmojiEntry('🇹🇰', ['flag_tk', 'tk']),
  EmojiEntry('🇧🇻', ['flag_bv', 'bv']),
  EmojiEntry('🇭🇲', ['flag_hm', 'hm']),
  EmojiEntry('🇸🇯', ['flag_sj', 'sj']),
  EmojiEntry('🇺🇲', ['flag_um', 'um']),
  EmojiEntry('🇮🇨', ['flag_ic', 'ic']),
  EmojiEntry('🇪🇦', ['flag_ea', 'ea']),
  EmojiEntry('🇨🇵', ['flag_cp', 'cp']),
  EmojiEntry('🇩🇬', ['flag_dg', 'dg']),
  EmojiEntry('🇦🇸', ['flag_as', 'as']),
  EmojiEntry('🇦🇶', ['flag_aq', 'aq']),
  EmojiEntry('🇻🇬', ['flag_vg', 'vg']),
  EmojiEntry('🇨🇰', ['flag_ck', 'ck']),
  EmojiEntry('🇨🇼', ['flag_cw', 'cw']),
  EmojiEntry('🇪🇺', ['flag_eu', 'eu']),
  EmojiEntry('🇬🇫', ['flag_gf', 'gf']),
  EmojiEntry('🇹🇫', ['flag_tf', 'tf']),
  EmojiEntry('🇬🇵', ['flag_gp', 'gp']),
  EmojiEntry('🇲🇶', ['flag_mq', 'mq']),
  EmojiEntry('🇲🇵', ['flag_mp', 'mp']),
  EmojiEntry('🇷🇪', ['flag_re', 're']),
  EmojiEntry('🇸🇽', ['flag_sx', 'sx']),
  EmojiEntry('🇸🇸', ['flag_ss', 'ss']),
  EmojiEntry('🇹🇨', ['flag_tc', 'tc']),
  EmojiEntry('🇲🇫', ['flag_mf', 'mf']),
  EmojiEntry('🕵🏻', ['detective_tone1', 'spy_tone1', 'sleuth_or_spy_tone1']),
  EmojiEntry('🕵🏼', ['detective_tone2', 'spy_tone2', 'sleuth_or_spy_tone2']),
  EmojiEntry('🕵🏽', ['detective_tone3', 'spy_tone3', 'sleuth_or_spy_tone3']),
  EmojiEntry('🕵🏾', ['detective_tone4', 'spy_tone4', 'sleuth_or_spy_tone4']),
  EmojiEntry('🕵🏿', ['detective_tone5', 'spy_tone5', 'sleuth_or_spy_tone5']),
  EmojiEntry('🥁', ['drum', 'drum_with_drumsticks']),
  EmojiEntry('🦐', ['shrimp']),
  EmojiEntry('🦑', ['squid']),
  EmojiEntry('🥚', ['egg']),
  EmojiEntry('🥛', ['milk', 'glass_of_milk']),
  EmojiEntry('🥜', ['peanuts', 'shelled_peanut']),
  EmojiEntry('🥝', ['kiwi', 'kiwifruit']),
  EmojiEntry('🥞', ['pancakes']),
  EmojiEntry('🇼', ['regional_indicator_w']),
  EmojiEntry('🇻', ['regional_indicator_v']),
  EmojiEntry('🇺', ['regional_indicator_u']),
  EmojiEntry('🇹', ['regional_indicator_t']),
  EmojiEntry('🇸', ['regional_indicator_s']),
  EmojiEntry('🇷', ['regional_indicator_r']),
  EmojiEntry('🇶', ['regional_indicator_q']),
  EmojiEntry('🇵', ['regional_indicator_p']),
  EmojiEntry('🇴', ['regional_indicator_o']),
  EmojiEntry('🇳', ['regional_indicator_n']),
  EmojiEntry('🇲', ['regional_indicator_m']),
  EmojiEntry('🇱', ['regional_indicator_l']),
  EmojiEntry('🇰', ['regional_indicator_k']),
  EmojiEntry('🇯', ['regional_indicator_j']),
  EmojiEntry('🇮', ['regional_indicator_i']),
  EmojiEntry('🇭', ['regional_indicator_h']),
  EmojiEntry('🇬', ['regional_indicator_g']),
  EmojiEntry('🇫', ['regional_indicator_f']),
  EmojiEntry('🇪', ['regional_indicator_e']),
  EmojiEntry('🇩', ['regional_indicator_d']),
  EmojiEntry('🇨', ['regional_indicator_c']),
  EmojiEntry('🇧', ['regional_indicator_b']),
  EmojiEntry('🇦', ['regional_indicator_a']),
  EmojiEntry('9️', ['digit_nine']),
  EmojiEntry('8️', ['digit_eight']),
  EmojiEntry('7️', ['digit_seven']),
  EmojiEntry('6️', ['digit_six']),
  EmojiEntry('5️', ['digit_five']),
  EmojiEntry('4️', ['digit_four']),
  EmojiEntry('3️', ['digit_three']),
  EmojiEntry('2️', ['digit_two']),
  EmojiEntry('1️', ['digit_one']),
  EmojiEntry('0️', ['digit_zero']),
  EmojiEntry('👯‍♂️', ['men_with_bunny_ears_partying']),
  EmojiEntry('👯‍♀️', ['women_with_bunny_ears_partying']),
  EmojiEntry('🏂🏻', ['snowboarder_tone1', 'snowboarder_light_skin_tone']),
  EmojiEntry('🏌️‍♂️', ['man_golfing']),
  EmojiEntry('🏌🏻‍♂️', ['man_golfing_tone1', 'man_golfing_light_skin_tone']),
  EmojiEntry('🏌🏼‍♂️', ['man_golfing_tone2', 'man_golfing_medium_light_skin_tone']),
  EmojiEntry('🏌🏽‍♂️', ['man_golfing_tone3', 'man_golfing_medium_skin_tone']),
  EmojiEntry('🏌🏾‍♂️', ['man_golfing_tone4', 'man_golfing_medium_dark_skin_tone']),
  EmojiEntry('🏌🏿‍♂️', ['man_golfing_tone5', 'man_golfing_dark_skin_tone']),
  EmojiEntry('🏌️‍♀️', ['woman_golfing']),
  EmojiEntry('🏌🏻‍♀️', ['woman_golfing_tone1', 'woman_golfing_light_skin_tone']),
  EmojiEntry('🏌🏼‍♀️', ['woman_golfing_tone2', 'woman_golfing_medium_light_skin_tone']),
  EmojiEntry('🏌🏽‍♀️', ['woman_golfing_tone3', 'woman_golfing_medium_skin_tone']),
  EmojiEntry('🏌🏾‍♀️', ['woman_golfing_tone4', 'woman_golfing_medium_dark_skin_tone']),
  EmojiEntry('🏌🏿‍♀️', ['woman_golfing_tone5', 'woman_golfing_dark_skin_tone']),
  EmojiEntry('🤼‍♂️', ['men_wrestling']),
  EmojiEntry('🤼‍♀️', ['women_wrestling']),
  EmojiEntry('🤹🏿‍♂️', ['man_juggling_tone5', 'man_juggling_dark_skin_tone']),
  EmojiEntry('🤹🏾‍♂️', ['man_juggling_tone4', 'man_juggling_medium_dark_skin_tone']),
  EmojiEntry('🤹🏽‍♂️', ['man_juggling_tone3', 'man_juggling_medium_skin_tone']),
  EmojiEntry('🤹🏼‍♂️', ['man_juggling_tone2', 'man_juggling_medium_light_skin_tone']),
  EmojiEntry('🤹🏻‍♂️', ['man_juggling_tone1', 'man_juggling_light_skin_tone']),
  EmojiEntry('🤹‍♂️', ['man_juggling']),
  EmojiEntry('🤹🏿‍♀️', ['woman_juggling_tone5', 'woman_juggling_dark_skin_tone']),
  EmojiEntry('🤹🏾‍♀️', ['woman_juggling_tone4', 'woman_juggling_medium_dark_skin_tone']),
  EmojiEntry('🤹🏽‍♀️', ['woman_juggling_tone3', 'woman_juggling_medium_skin_tone']),
  EmojiEntry('🤹🏼‍♀️', ['woman_juggling_tone2', 'woman_juggling_medium_light_skin_tone']),
  EmojiEntry('🤹🏻‍♀️', ['woman_juggling_tone1', 'woman_juggling_light_skin_tone']),
  EmojiEntry('🤹‍♀️', ['woman_juggling']),
  EmojiEntry('🤾🏿‍♂️', ['man_playing_handball_tone5', 'man_playing_handball_dark_skin_tone']),
  EmojiEntry('🤾🏾‍♂️', ['man_playing_handball_tone4', 'man_playing_handball_medium_dark_skin_tone']),
  EmojiEntry('🤾🏽‍♂️', ['man_playing_handball_tone3', 'man_playing_handball_medium_skin_tone']),
  EmojiEntry('🤾🏼‍♂️', ['man_playing_handball_tone2', 'man_playing_handball_medium_light_skin_tone']),
  EmojiEntry('🤾🏻‍♂️', ['man_playing_handball_tone1', 'man_playing_handball_light_skin_tone']),
  EmojiEntry('🤾‍♂️', ['man_playing_handball']),
  EmojiEntry('🤾🏿‍♀️', ['woman_playing_handball_tone5', 'woman_playing_handball_dark_skin_tone']),
  EmojiEntry('🤾🏾‍♀️', ['woman_playing_handball_tone4', 'woman_playing_handball_medium_dark_skin_tone']),
  EmojiEntry('🤾🏽‍♀️', ['woman_playing_handball_tone3', 'woman_playing_handball_medium_skin_tone']),
  EmojiEntry('🤾🏼‍♀️', ['woman_playing_handball_tone2', 'woman_playing_handball_medium_light_skin_tone']),
  EmojiEntry('🤾🏻‍♀️', ['woman_playing_handball_tone1', 'woman_playing_handball_light_skin_tone']),
  EmojiEntry('🤾‍♀️', ['woman_playing_handball']),
  EmojiEntry('🤽🏿‍♂️', ['man_playing_water_polo_tone5', 'man_playing_water_polo_dark_skin_tone']),
  EmojiEntry('🤽🏾‍♂️', ['man_playing_water_polo_tone4', 'man_playing_water_polo_medium_dark_skin_tone']),
  EmojiEntry('🤽🏽‍♂️', ['man_playing_water_polo_tone3', 'man_playing_water_polo_medium_skin_tone']),
  EmojiEntry('🤽🏼‍♂️', ['man_playing_water_polo_tone2', 'man_playing_water_polo_medium_light_skin_tone']),
  EmojiEntry('🤽🏻‍♂️', ['man_playing_water_polo_tone1', 'man_playing_water_polo_light_skin_tone']),
  EmojiEntry('🤽‍♂️', ['man_playing_water_polo']),
  EmojiEntry('🤽🏿‍♀️', ['woman_playing_water_polo_tone5', 'woman_playing_water_polo_dark_skin_tone']),
  EmojiEntry('🤽🏾‍♀️', ['woman_playing_water_polo_tone4', 'woman_playing_water_polo_medium_dark_skin_tone']),
  EmojiEntry('🤽🏽‍♀️', ['woman_playing_water_polo_tone3', 'woman_playing_water_polo_medium_skin_tone']),
  EmojiEntry('🤽🏼‍♀️', ['woman_playing_water_polo_tone2', 'woman_playing_water_polo_medium_light_skin_tone']),
  EmojiEntry('🤽🏻‍♀️', ['woman_playing_water_polo_tone1', 'woman_playing_water_polo_light_skin_tone']),
  EmojiEntry('🤽‍♀️', ['woman_playing_water_polo']),
  EmojiEntry('🤸🏿‍♂️', ['man_cartwheeling_tone5', 'man_cartwheeling_dark_skin_tone']),
  EmojiEntry('🤸🏾‍♂️', ['man_cartwheeling_tone4', 'man_cartwheeling_medium_dark_skin_tone']),
  EmojiEntry('🤸🏽‍♂️', ['man_cartwheeling_tone3', 'man_cartwheeling_medium_skin_tone']),
  EmojiEntry('🤸🏼‍♂️', ['man_cartwheeling_tone2', 'man_cartwheeling_medium_light_skin_tone']),
  EmojiEntry('🤸🏻‍♂️', ['man_cartwheeling_tone1', 'man_cartwheeling_light_skin_tone']),
  EmojiEntry('🤸‍♂️', ['man_cartwheeling']),
  EmojiEntry('🤸🏿‍♀️', ['woman_cartwheeling_tone5', 'woman_cartwheeling_dark_skin_tone']),
  EmojiEntry('🤸🏾‍♀️', ['woman_cartwheeling_tone4', 'woman_cartwheeling_medium_dark_skin_tone']),
  EmojiEntry('🤸🏽‍♀️', ['woman_cartwheeling_tone3', 'woman_cartwheeling_medium_skin_tone']),
  EmojiEntry('🤸🏼‍♀️', ['woman_cartwheeling_tone2', 'woman_cartwheeling_medium_light_skin_tone']),
  EmojiEntry('🤸🏻‍♀️', ['woman_cartwheeling_tone1', 'woman_cartwheeling_light_skin_tone']),
  EmojiEntry('🤸‍♀️', ['woman_cartwheeling']),
  EmojiEntry('🚶🏿‍♂️', ['man_walking_tone5', 'man_walking_dark_skin_tone']),
  EmojiEntry('🚶🏾‍♂️', ['man_walking_tone4', 'man_walking_medium_dark_skin_tone']),
  EmojiEntry('🚶🏽‍♂️', ['man_walking_tone3', 'man_walking_medium_skin_tone']),
  EmojiEntry('🚶🏼‍♂️', ['man_walking_tone2', 'man_walking_medium_light_skin_tone']),
  EmojiEntry('🚶🏻‍♂️', ['man_walking_tone1', 'man_walking_light_skin_tone']),
  EmojiEntry('🚶‍♂️', ['man_walking']),
  EmojiEntry('🚶🏿‍♀️', ['woman_walking_tone5', 'woman_walking_dark_skin_tone']),
  EmojiEntry('🚶🏾‍♀️', ['woman_walking_tone4', 'woman_walking_medium_dark_skin_tone']),
  EmojiEntry('🚶🏽‍♀️', ['woman_walking_tone3', 'woman_walking_medium_skin_tone']),
  EmojiEntry('🚶🏼‍♀️', ['woman_walking_tone2', 'woman_walking_medium_light_skin_tone']),
  EmojiEntry('🚶🏻‍♀️', ['woman_walking_tone1', 'woman_walking_light_skin_tone']),
  EmojiEntry('🚶‍♀️', ['woman_walking']),
  EmojiEntry('🚵🏿‍♂️', ['man_mountain_biking_tone5', 'man_mountain_biking_dark_skin_tone']),
  EmojiEntry('🚵🏾‍♂️', ['man_mountain_biking_tone4', 'man_mountain_biking_medium_dark_skin_tone']),
  EmojiEntry('🚵🏽‍♂️', ['man_mountain_biking_tone3', 'man_mountain_biking_medium_skin_tone']),
  EmojiEntry('🚵🏼‍♂️', ['man_mountain_biking_tone2', 'man_mountain_biking_medium_light_skin_tone']),
  EmojiEntry('🚵🏻‍♂️', ['man_mountain_biking_tone1', 'man_mountain_biking_light_skin_tone']),
  EmojiEntry('🚵‍♂️', ['man_mountain_biking']),
  EmojiEntry('🚵🏿‍♀️', ['woman_mountain_biking_tone5', 'woman_mountain_biking_dark_skin_tone']),
  EmojiEntry('🚵🏾‍♀️', ['woman_mountain_biking_tone4', 'woman_mountain_biking_medium_dark_skin_tone']),
  EmojiEntry('🚵🏽‍♀️', ['woman_mountain_biking_tone3', 'woman_mountain_biking_medium_skin_tone']),
  EmojiEntry('🚵🏼‍♀️', ['woman_mountain_biking_tone2', 'woman_mountain_biking_medium_light_skin_tone']),
  EmojiEntry('🚵🏻‍♀️', ['woman_mountain_biking_tone1', 'woman_mountain_biking_light_skin_tone']),
  EmojiEntry('🚵‍♀️', ['woman_mountain_biking']),
  EmojiEntry('🚴🏿‍♂️', ['man_biking_tone5', 'man_biking_dark_skin_tone']),
  EmojiEntry('🚴🏾‍♂️', ['man_biking_tone4', 'man_biking_medium_dark_skin_tone']),
  EmojiEntry('🚴🏽‍♂️', ['man_biking_tone3', 'man_biking_medium_skin_tone']),
  EmojiEntry('🚴🏼‍♂️', ['man_biking_tone2', 'man_biking_medium_light_skin_tone']),
  EmojiEntry('🚴🏻‍♂️', ['man_biking_tone1', 'man_biking_light_skin_tone']),
  EmojiEntry('🚴‍♂️', ['man_biking']),
  EmojiEntry('🚴🏿‍♀️', ['woman_biking_tone5', 'woman_biking_dark_skin_tone']),
  EmojiEntry('🚴🏾‍♀️', ['woman_biking_tone4', 'woman_biking_medium_dark_skin_tone']),
  EmojiEntry('🚴🏽‍♀️', ['woman_biking_tone3', 'woman_biking_medium_skin_tone']),
  EmojiEntry('🚴🏼‍♀️', ['woman_biking_tone2', 'woman_biking_medium_light_skin_tone']),
  EmojiEntry('🚴🏻‍♀️', ['woman_biking_tone1', 'woman_biking_light_skin_tone']),
  EmojiEntry('🚴‍♀️', ['woman_biking']),
  EmojiEntry('🚣🏿‍♂️', ['man_rowing_boat_tone5', 'man_rowing_boat_dark_skin_tone']),
  EmojiEntry('🚣🏾‍♂️', ['man_rowing_boat_tone4', 'man_rowing_boat_medium_dark_skin_tone']),
  EmojiEntry('🚣🏽‍♂️', ['man_rowing_boat_tone3', 'man_rowing_boat_medium_skin_tone']),
  EmojiEntry('🚣🏼‍♂️', ['man_rowing_boat_tone2', 'man_rowing_boat_medium_light_skin_tone']),
  EmojiEntry('🚣🏻‍♂️', ['man_rowing_boat_tone1', 'man_rowing_boat_light_skin_tone']),
  EmojiEntry('🚣‍♂️', ['man_rowing_boat']),
  EmojiEntry('🚣🏿‍♀️', ['woman_rowing_boat_tone5', 'woman_rowing_boat_dark_skin_tone']),
  EmojiEntry('🚣🏾‍♀️', ['woman_rowing_boat_tone4', 'woman_rowing_boat_medium_dark_skin_tone']),
  EmojiEntry('🚣🏽‍♀️', ['woman_rowing_boat_tone3', 'woman_rowing_boat_medium_skin_tone']),
  EmojiEntry('🚣🏼‍♀️', ['woman_rowing_boat_tone2', 'woman_rowing_boat_medium_light_skin_tone']),
  EmojiEntry('🚣🏻‍♀️', ['woman_rowing_boat_tone1', 'woman_rowing_boat_light_skin_tone']),
  EmojiEntry('🚣‍♀️', ['woman_rowing_boat']),
  EmojiEntry('🏋🏿‍♂️', ['man_lifting_weights_tone5', 'man_lifting_weights_dark_skin_tone']),
  EmojiEntry('🏋🏾‍♂️', ['man_lifting_weights_tone4', 'man_lifting_weights_medium_dark_skin_tone']),
  EmojiEntry('🏋🏽‍♂️', ['man_lifting_weights_tone3', 'man_lifting_weights_medium_skin_tone']),
  EmojiEntry('🏋🏼‍♂️', ['man_lifting_weights_tone2', 'man_lifting_weights_medium_light_skin_tone']),
  EmojiEntry('🏋🏻‍♂️', ['man_lifting_weights_tone1', 'man_lifting_weights_light_skin_tone']),
  EmojiEntry('🏋️‍♂️', ['man_lifting_weights']),
  EmojiEntry('🏋🏿‍♀️', ['woman_lifting_weights_tone5', 'woman_lifting_weights_dark_skin_tone']),
  EmojiEntry('🏋🏾‍♀️', ['woman_lifting_weights_tone4', 'woman_lifting_weights_medium_dark_skin_tone']),
  EmojiEntry('🏋🏽‍♀️', ['woman_lifting_weights_tone3', 'woman_lifting_weights_medium_skin_tone']),
  EmojiEntry('🏋🏼‍♀️', ['woman_lifting_weights_tone2', 'woman_lifting_weights_medium_light_skin_tone']),
  EmojiEntry('🏋🏻‍♀️', ['woman_lifting_weights_tone1', 'woman_lifting_weights_light_skin_tone']),
  EmojiEntry('🏋️‍♀️', ['woman_lifting_weights']),
  EmojiEntry('🏊🏿‍♂️', ['man_swimming_tone5', 'man_swimming_dark_skin_tone']),
  EmojiEntry('🏊🏾‍♂️', ['man_swimming_tone4', 'man_swimming_medium_dark_skin_tone']),
  EmojiEntry('🏊🏽‍♂️', ['man_swimming_tone3', 'man_swimming_medium_skin_tone']),
  EmojiEntry('🏊🏼‍♂️', ['man_swimming_tone2', 'man_swimming_medium_light_skin_tone']),
  EmojiEntry('🏊🏻‍♂️', ['man_swimming_tone1', 'man_swimming_light_skin_tone']),
  EmojiEntry('🏊‍♂️', ['man_swimming']),
  EmojiEntry('🏊🏿‍♀️', ['woman_swimming_tone5', 'woman_swimming_dark_skin_tone']),
  EmojiEntry('🏊🏾‍♀️', ['woman_swimming_tone4', 'woman_swimming_medium_dark_skin_tone']),
  EmojiEntry('🏊🏽‍♀️', ['woman_swimming_tone3', 'woman_swimming_medium_skin_tone']),
  EmojiEntry('🏊🏼‍♀️', ['woman_swimming_tone2', 'woman_swimming_medium_light_skin_tone']),
  EmojiEntry('🏊🏻‍♀️', ['woman_swimming_tone1', 'woman_swimming_light_skin_tone']),
  EmojiEntry('🏊‍♀️', ['woman_swimming']),
  EmojiEntry('🏄🏿‍♂️', ['man_surfing_tone5', 'man_surfing_dark_skin_tone']),
  EmojiEntry('🏄🏾‍♂️', ['man_surfing_tone4', 'man_surfing_medium_dark_skin_tone']),
  EmojiEntry('🏄🏽‍♂️', ['man_surfing_tone3', 'man_surfing_medium_skin_tone']),
  EmojiEntry('🏄🏼‍♂️', ['man_surfing_tone2', 'man_surfing_medium_light_skin_tone']),
  EmojiEntry('🏄🏻‍♂️', ['man_surfing_tone1', 'man_surfing_light_skin_tone']),
  EmojiEntry('🏄‍♂️', ['man_surfing']),
  EmojiEntry('🏄🏿‍♀️', ['woman_surfing_tone5', 'woman_surfing_dark_skin_tone']),
  EmojiEntry('🏄🏾‍♀️', ['woman_surfing_tone4', 'woman_surfing_medium_dark_skin_tone']),
  EmojiEntry('🏄🏽‍♀️', ['woman_surfing_tone3', 'woman_surfing_medium_skin_tone']),
  EmojiEntry('🏄🏼‍♀️', ['woman_surfing_tone2', 'woman_surfing_medium_light_skin_tone']),
  EmojiEntry('🏄🏻‍♀️', ['woman_surfing_tone1', 'woman_surfing_light_skin_tone']),
  EmojiEntry('🏄‍♀️', ['woman_surfing']),
  EmojiEntry('🏃🏿‍♂️', ['man_running_tone5', 'man_running_dark_skin_tone']),
  EmojiEntry('🏃🏾‍♂️', ['man_running_tone4', 'man_running_medium_dark_skin_tone']),
  EmojiEntry('🏃🏽‍♂️', ['man_running_tone3', 'man_running_medium_skin_tone']),
  EmojiEntry('🏃🏼‍♂️', ['man_running_tone2', 'man_running_medium_light_skin_tone']),
  EmojiEntry('🏃🏻‍♂️', ['man_running_tone1', 'man_running_light_skin_tone']),
  EmojiEntry('🏃‍♂️', ['man_running']),
  EmojiEntry('🏃🏿‍♀️', ['woman_running_tone5', 'woman_running_dark_skin_tone']),
  EmojiEntry('🏃🏾‍♀️', ['woman_running_tone4', 'woman_running_medium_dark_skin_tone']),
  EmojiEntry('🏃🏽‍♀️', ['woman_running_tone3', 'woman_running_medium_skin_tone']),
  EmojiEntry('🏃🏼‍♀️', ['woman_running_tone2', 'woman_running_medium_light_skin_tone']),
  EmojiEntry('🏃🏻‍♀️', ['woman_running_tone1', 'woman_running_light_skin_tone']),
  EmojiEntry('🏃‍♀️', ['woman_running']),
  EmojiEntry('⛹🏿‍♂️', ['man_bouncing_ball_tone5', 'man_bouncing_ball_dark_skin_tone']),
  EmojiEntry('⛹🏾‍♂️', ['man_bouncing_ball_tone4', 'man_bouncing_ball_medium_dark_skin_tone']),
  EmojiEntry('⛹🏽‍♂️', ['man_bouncing_ball_tone3', 'man_bouncing_ball_medium_skin_tone']),
  EmojiEntry('⛹🏼‍♂️', ['man_bouncing_ball_tone2', 'man_bouncing_ball_medium_light_skin_tone']),
  EmojiEntry('⛹🏻‍♂️', ['man_bouncing_ball_tone1', 'man_bouncing_ball_light_skin_tone']),
  EmojiEntry('⛹️‍♂️', ['man_bouncing_ball']),
  EmojiEntry('⛹🏿‍♀️', ['woman_bouncing_ball_tone5', 'woman_bouncing_ball_dark_skin_tone']),
  EmojiEntry('⛹🏾‍♀️', ['woman_bouncing_ball_tone4', 'woman_bouncing_ball_medium_dark_skin_tone']),
  EmojiEntry('⛹🏽‍♀️', ['woman_bouncing_ball_tone3', 'woman_bouncing_ball_medium_skin_tone']),
  EmojiEntry('⛹🏼‍♀️', ['woman_bouncing_ball_tone2', 'woman_bouncing_ball_medium_light_skin_tone']),
  EmojiEntry('⛹🏻‍♀️', ['woman_bouncing_ball_tone1', 'woman_bouncing_ball_light_skin_tone']),
  EmojiEntry('⛹️‍♀️', ['woman_bouncing_ball']),
  EmojiEntry('🤷🏿‍♂️', ['man_shrugging_tone5', 'man_shrugging_dark_skin_tone']),
  EmojiEntry('🤷🏾‍♂️', ['man_shrugging_tone4', 'man_shrugging_medium_dark_skin_tone']),
  EmojiEntry('🤷🏽‍♂️', ['man_shrugging_tone3', 'man_shrugging_medium_skin_tone']),
  EmojiEntry('🤷🏼‍♂️', ['man_shrugging_tone2', 'man_shrugging_medium_light_skin_tone']),
  EmojiEntry('🤷🏻‍♂️', ['man_shrugging_tone1', 'man_shrugging_light_skin_tone']),
  EmojiEntry('🤷‍♂️', ['man_shrugging']),
  EmojiEntry('🤷🏿‍♀️', ['woman_shrugging_tone5', 'woman_shrugging_dark_skin_tone']),
  EmojiEntry('🤷🏾‍♀️', ['woman_shrugging_tone4', 'woman_shrugging_medium_dark_skin_tone']),
  EmojiEntry('🤷🏽‍♀️', ['woman_shrugging_tone3', 'woman_shrugging_medium_skin_tone']),
  EmojiEntry('🤷🏼‍♀️', ['woman_shrugging_tone2', 'woman_shrugging_medium_light_skin_tone']),
  EmojiEntry('🤷🏻‍♀️', ['woman_shrugging_tone1', 'woman_shrugging_light_skin_tone']),
  EmojiEntry('🤷‍♀️', ['woman_shrugging']),
  EmojiEntry('🤦🏿‍♂️', ['man_facepalming_tone5', 'man_facepalming_dark_skin_tone']),
  EmojiEntry('🤦🏾‍♂️', ['man_facepalming_tone4', 'man_facepalming_medium_dark_skin_tone']),
  EmojiEntry('🤦🏽‍♂️', ['man_facepalming_tone3', 'man_facepalming_medium_skin_tone']),
  EmojiEntry('🤦🏼‍♂️', ['man_facepalming_tone2', 'man_facepalming_medium_light_skin_tone']),
  EmojiEntry('🤦🏻‍♂️', ['man_facepalming_tone1', 'man_facepalming_light_skin_tone']),
  EmojiEntry('🤦‍♂️', ['man_facepalming']),
  EmojiEntry('🤦🏿‍♀️', ['woman_facepalming_tone5', 'woman_facepalming_dark_skin_tone']),
  EmojiEntry('🤦🏾‍♀️', ['woman_facepalming_tone4', 'woman_facepalming_medium_dark_skin_tone']),
  EmojiEntry('🤦🏽‍♀️', ['woman_facepalming_tone3', 'woman_facepalming_medium_skin_tone']),
  EmojiEntry('🤦🏼‍♀️', ['woman_facepalming_tone2', 'woman_facepalming_medium_light_skin_tone']),
  EmojiEntry('🤦🏻‍♀️', ['woman_facepalming_tone1', 'woman_facepalming_light_skin_tone']),
  EmojiEntry('🤦‍♀️', ['woman_facepalming']),
  EmojiEntry('🙎🏿‍♂️', ['man_pouting_tone5', 'man_pouting_dark_skin_tone']),
  EmojiEntry('🙎🏾‍♂️', ['man_pouting_tone4', 'man_pouting_medium_dark_skin_tone']),
  EmojiEntry('🙎🏽‍♂️', ['man_pouting_tone3', 'man_pouting_medium_skin_tone']),
  EmojiEntry('🙎🏼‍♂️', ['man_pouting_tone2', 'man_pouting_medium_light_skin_tone']),
  EmojiEntry('🙎🏻‍♂️', ['man_pouting_tone1', 'man_pouting_light_skin_tone']),
  EmojiEntry('🙎‍♂️', ['man_pouting']),
  EmojiEntry('🙎🏿‍♀️', ['woman_pouting_tone5', 'woman_pouting_dark_skin_tone']),
  EmojiEntry('🙎🏾‍♀️', ['woman_pouting_tone4', 'woman_pouting_medium_dark_skin_tone']),
  EmojiEntry('🙎🏽‍♀️', ['woman_pouting_tone3', 'woman_pouting_medium_skin_tone']),
  EmojiEntry('🙎🏼‍♀️', ['woman_pouting_tone2', 'woman_pouting_medium_light_skin_tone']),
  EmojiEntry('🙎🏻‍♀️', ['woman_pouting_tone1', 'woman_pouting_light_skin_tone']),
  EmojiEntry('🙎‍♀️', ['woman_pouting']),
  EmojiEntry('🙍🏿‍♂️', ['man_frowning_tone5', 'man_frowning_dark_skin_tone']),
  EmojiEntry('🙍🏾‍♂️', ['man_frowning_tone4', 'man_frowning_medium_dark_skin_tone']),
  EmojiEntry('🙍🏽‍♂️', ['man_frowning_tone3', 'man_frowning_medium_skin_tone']),
  EmojiEntry('🙍🏼‍♂️', ['man_frowning_tone2', 'man_frowning_medium_light_skin_tone']),
  EmojiEntry('🙍🏻‍♂️', ['man_frowning_tone1', 'man_frowning_light_skin_tone']),
  EmojiEntry('🙍‍♂️', ['man_frowning']),
  EmojiEntry('🙍🏿‍♀️', ['woman_frowning_tone5', 'woman_frowning_dark_skin_tone']),
  EmojiEntry('🙍🏾‍♀️', ['woman_frowning_tone4', 'woman_frowning_medium_dark_skin_tone']),
  EmojiEntry('🙍🏽‍♀️', ['woman_frowning_tone3', 'woman_frowning_medium_skin_tone']),
  EmojiEntry('🙍🏼‍♀️', ['woman_frowning_tone2', 'woman_frowning_medium_light_skin_tone']),
  EmojiEntry('🙍🏻‍♀️', ['woman_frowning_tone1', 'woman_frowning_light_skin_tone']),
  EmojiEntry('🙍‍♀️', ['woman_frowning']),
  EmojiEntry('🙋🏿‍♂️', ['man_raising_hand_tone5', 'man_raising_hand_dark_skin_tone']),
  EmojiEntry('🙋🏾‍♂️', ['man_raising_hand_tone4', 'man_raising_hand_medium_dark_skin_tone']),
  EmojiEntry('🙋🏽‍♂️', ['man_raising_hand_tone3', 'man_raising_hand_medium_skin_tone']),
  EmojiEntry('🙋🏼‍♂️', ['man_raising_hand_tone2', 'man_raising_hand_medium_light_skin_tone']),
  EmojiEntry('🙋🏻‍♂️', ['man_raising_hand_tone1', 'man_raising_hand_light_skin_tone']),
  EmojiEntry('🙋‍♂️', ['man_raising_hand']),
  EmojiEntry('🙋🏿‍♀️', ['woman_raising_hand_tone5', 'woman_raising_hand_dark_skin_tone']),
  EmojiEntry('🙋🏾‍♀️', ['woman_raising_hand_tone4', 'woman_raising_hand_medium_dark_skin_tone']),
  EmojiEntry('🙋🏽‍♀️', ['woman_raising_hand_tone3', 'woman_raising_hand_medium_skin_tone']),
  EmojiEntry('🙋🏼‍♀️', ['woman_raising_hand_tone2', 'woman_raising_hand_medium_light_skin_tone']),
  EmojiEntry('🙋🏻‍♀️', ['woman_raising_hand_tone1', 'woman_raising_hand_light_skin_tone']),
  EmojiEntry('🙋‍♀️', ['woman_raising_hand']),
  EmojiEntry('🙇🏿‍♂️', ['man_bowing_tone5', 'man_bowing_dark_skin_tone']),
  EmojiEntry('🙇🏾‍♂️', ['man_bowing_tone4', 'man_bowing_medium_dark_skin_tone']),
  EmojiEntry('🙇🏽‍♂️', ['man_bowing_tone3', 'man_bowing_medium_skin_tone']),
  EmojiEntry('🙇🏼‍♂️', ['man_bowing_tone2', 'man_bowing_medium_light_skin_tone']),
  EmojiEntry('🙇🏻‍♂️', ['man_bowing_tone1', 'man_bowing_light_skin_tone']),
  EmojiEntry('🙇‍♂️', ['man_bowing']),
  EmojiEntry('🙇🏿‍♀️', ['woman_bowing_tone5', 'woman_bowing_dark_skin_tone']),
  EmojiEntry('🙇🏾‍♀️', ['woman_bowing_tone4', 'woman_bowing_medium_dark_skin_tone']),
  EmojiEntry('🙇🏽‍♀️', ['woman_bowing_tone3', 'woman_bowing_medium_skin_tone']),
  EmojiEntry('🙇🏼‍♀️', ['woman_bowing_tone2', 'woman_bowing_medium_light_skin_tone']),
  EmojiEntry('🙇🏻‍♀️', ['woman_bowing_tone1', 'woman_bowing_light_skin_tone']),
  EmojiEntry('🙇‍♀️', ['woman_bowing']),
  EmojiEntry('🙆🏿‍♂️', ['man_gesturing_ok_tone5', 'man_gesturing_ok_dark_skin_tone']),
  EmojiEntry('🙆🏾‍♂️', ['man_gesturing_ok_tone4', 'man_gesturing_ok_medium_dark_skin_tone']),
  EmojiEntry('🙆🏽‍♂️', ['man_gesturing_ok_tone3', 'man_gesturing_ok_medium_skin_tone']),
  EmojiEntry('🙆🏼‍♂️', ['man_gesturing_ok_tone2', 'man_gesturing_ok_medium_light_skin_tone']),
  EmojiEntry('🙆🏻‍♂️', ['man_gesturing_ok_tone1', 'man_gesturing_ok_light_skin_tone']),
  EmojiEntry('🙆‍♂️', ['man_gesturing_ok']),
  EmojiEntry('🙆🏿‍♀️', ['woman_gesturing_ok_tone5', 'woman_gesturing_ok_dark_skin_tone']),
  EmojiEntry('🙆🏾‍♀️', ['woman_gesturing_ok_tone4', 'woman_gesturing_ok_medium_dark_skin_tone']),
  EmojiEntry('🙆🏽‍♀️', ['woman_gesturing_ok_tone3', 'woman_gesturing_ok_medium_skin_tone']),
  EmojiEntry('🙆🏼‍♀️', ['woman_gesturing_ok_tone2', 'woman_gesturing_ok_medium_light_skin_tone']),
  EmojiEntry('🙆🏻‍♀️', ['woman_gesturing_ok_tone1', 'woman_gesturing_ok_light_skin_tone']),
  EmojiEntry('🙆‍♀️', ['woman_gesturing_ok']),
  EmojiEntry('🙅🏿‍♂️', ['man_gesturing_no_tone5', 'man_gesturing_no_dark_skin_tone']),
  EmojiEntry('🙅🏾‍♂️', ['man_gesturing_no_tone4', 'man_gesturing_no_medium_dark_skin_tone']),
  EmojiEntry('🙅🏽‍♂️', ['man_gesturing_no_tone3', 'man_gesturing_no_medium_skin_tone']),
  EmojiEntry('🙅🏼‍♂️', ['man_gesturing_no_tone2', 'man_gesturing_no_medium_light_skin_tone']),
  EmojiEntry('🙅🏻‍♂️', ['man_gesturing_no_tone1', 'man_gesturing_no_light_skin_tone']),
  EmojiEntry('🙅‍♂️', ['man_gesturing_no']),
  EmojiEntry('🙅🏿‍♀️', ['woman_gesturing_no_tone5', 'woman_gesturing_no_dark_skin_tone']),
  EmojiEntry('🙅🏾‍♀️', ['woman_gesturing_no_tone4', 'woman_gesturing_no_medium_dark_skin_tone']),
  EmojiEntry('🙅🏽‍♀️', ['woman_gesturing_no_tone3', 'woman_gesturing_no_medium_skin_tone']),
  EmojiEntry('🙅🏼‍♀️', ['woman_gesturing_no_tone2', 'woman_gesturing_no_medium_light_skin_tone']),
  EmojiEntry('🙅🏻‍♀️', ['woman_gesturing_no_tone1', 'woman_gesturing_no_light_skin_tone']),
  EmojiEntry('🙅‍♀️', ['woman_gesturing_no']),
  EmojiEntry('💇🏿‍♂️', ['man_getting_haircut_tone5', 'man_getting_haircut_dark_skin_tone']),
  EmojiEntry('💇🏾‍♂️', ['man_getting_haircut_tone4', 'man_getting_haircut_medium_dark_skin_tone']),
  EmojiEntry('💇🏽‍♂️', ['man_getting_haircut_tone3', 'man_getting_haircut_medium_skin_tone']),
  EmojiEntry('💇🏼‍♂️', ['man_getting_haircut_tone2', 'man_getting_haircut_medium_light_skin_tone']),
  EmojiEntry('💇🏻‍♂️', ['man_getting_haircut_tone1', 'man_getting_haircut_light_skin_tone']),
  EmojiEntry('💇‍♂️', ['man_getting_haircut']),
  EmojiEntry('💇🏿‍♀️', ['woman_getting_haircut_tone5', 'woman_getting_haircut_dark_skin_tone']),
  EmojiEntry('💇🏾‍♀️', ['woman_getting_haircut_tone4', 'woman_getting_haircut_medium_dark_skin_tone']),
  EmojiEntry('💇🏽‍♀️', ['woman_getting_haircut_tone3', 'woman_getting_haircut_medium_skin_tone']),
  EmojiEntry('💇🏼‍♀️', ['woman_getting_haircut_tone2', 'woman_getting_haircut_medium_light_skin_tone']),
  EmojiEntry('💇🏻‍♀️', ['woman_getting_haircut_tone1', 'woman_getting_haircut_light_skin_tone']),
  EmojiEntry('💇‍♀️', ['woman_getting_haircut']),
  EmojiEntry('💆🏿‍♂️', ['man_getting_face_massage_tone5', 'man_getting_face_massage_dark_skin_tone']),
  EmojiEntry('💆🏾‍♂️', ['man_getting_face_massage_tone4', 'man_getting_face_massage_medium_dark_skin_tone']),
  EmojiEntry('💆🏽‍♂️', ['man_getting_face_massage_tone3', 'man_getting_face_massage_medium_skin_tone']),
  EmojiEntry('💆🏼‍♂️', ['man_getting_face_massage_tone2', 'man_getting_face_massage_medium_light_skin_tone']),
  EmojiEntry('💆🏻‍♂️', ['man_getting_face_massage_tone1', 'man_getting_face_massage_light_skin_tone']),
  EmojiEntry('💆‍♂️', ['man_getting_face_massage']),
  EmojiEntry('💆🏿‍♀️', ['woman_getting_face_massage_tone5', 'woman_getting_face_massage_dark_skin_tone']),
  EmojiEntry('💆🏾‍♀️', ['woman_getting_face_massage_tone4', 'woman_getting_face_massage_medium_dark_skin_tone']),
  EmojiEntry('💆🏽‍♀️', ['woman_getting_face_massage_tone3', 'woman_getting_face_massage_medium_skin_tone']),
  EmojiEntry('💆🏼‍♀️', ['woman_getting_face_massage_tone2', 'woman_getting_face_massage_medium_light_skin_tone']),
  EmojiEntry('💆🏻‍♀️', ['woman_getting_face_massage_tone1', 'woman_getting_face_massage_light_skin_tone']),
  EmojiEntry('💆‍♀️', ['woman_getting_face_massage']),
  EmojiEntry('💁🏿‍♂️', ['man_tipping_hand_tone5', 'man_tipping_hand_dark_skin_tone']),
  EmojiEntry('💁🏾‍♂️', ['man_tipping_hand_tone4', 'man_tipping_hand_medium_dark_skin_tone']),
  EmojiEntry('💁🏽‍♂️', ['man_tipping_hand_tone3', 'man_tipping_hand_medium_skin_tone']),
  EmojiEntry('💁🏼‍♂️', ['man_tipping_hand_tone2', 'man_tipping_hand_medium_light_skin_tone']),
  EmojiEntry('💁🏻‍♂️', ['man_tipping_hand_tone1', 'man_tipping_hand_light_skin_tone']),
  EmojiEntry('💁‍♂️', ['man_tipping_hand']),
  EmojiEntry('💁🏿‍♀️', ['woman_tipping_hand_tone5', 'woman_tipping_hand_dark_skin_tone']),
  EmojiEntry('💁🏾‍♀️', ['woman_tipping_hand_tone4', 'woman_tipping_hand_medium_dark_skin_tone']),
  EmojiEntry('💁🏽‍♀️', ['woman_tipping_hand_tone3', 'woman_tipping_hand_medium_skin_tone']),
  EmojiEntry('💁🏼‍♀️', ['woman_tipping_hand_tone2', 'woman_tipping_hand_medium_light_skin_tone']),
  EmojiEntry('💁🏻‍♀️', ['woman_tipping_hand_tone1', 'woman_tipping_hand_light_skin_tone']),
  EmojiEntry('💁‍♀️', ['woman_tipping_hand']),
  EmojiEntry('👱🏿‍♂️', ['blond-haired_man_tone5', 'blond-haired_man_dark_skin_tone']),
  EmojiEntry('👱🏾‍♂️', ['blond-haired_man_tone4', 'blond-haired_man_medium_dark_skin_tone']),
  EmojiEntry('👱🏽‍♂️', ['blond-haired_man_tone3', 'blond-haired_man_medium_skin_tone']),
  EmojiEntry('👱🏼‍♂️', ['blond-haired_man_tone2', 'blond-haired_man_medium_light_skin_tone']),
  EmojiEntry('👱🏻‍♂️', ['blond-haired_man_tone1', 'blond-haired_man_light_skin_tone']),
  EmojiEntry('👱‍♂️', ['blond-haired_man']),
  EmojiEntry('👱🏿‍♀️', ['blond-haired_woman_tone5', 'blond-haired_woman_dark_skin_tone']),
  EmojiEntry('👱🏾‍♀️', ['blond-haired_woman_tone4', 'blond-haired_woman_medium_dark_skin_tone']),
  EmojiEntry('👱🏽‍♀️', ['blond-haired_woman_tone3', 'blond-haired_woman_medium_skin_tone']),
  EmojiEntry('👱🏼‍♀️', ['blond-haired_woman_tone2', 'blond-haired_woman_medium_light_skin_tone']),
  EmojiEntry('👱🏻‍♀️', ['blond-haired_woman_tone1', 'blond-haired_woman_light_skin_tone']),
  EmojiEntry('👱‍♀️', ['blond-haired_woman']),
  EmojiEntry('👳🏿‍♂️', ['man_wearing_turban_tone5', 'man_wearing_turban_dark_skin_tone']),
  EmojiEntry('👳🏾‍♂️', ['man_wearing_turban_tone4', 'man_wearing_turban_medium_dark_skin_tone']),
  EmojiEntry('👳🏽‍♂️', ['man_wearing_turban_tone3', 'man_wearing_turban_medium_skin_tone']),
  EmojiEntry('👳🏼‍♂️', ['man_wearing_turban_tone2', 'man_wearing_turban_medium_light_skin_tone']),
  EmojiEntry('👳🏻‍♂️', ['man_wearing_turban_tone1', 'man_wearing_turban_light_skin_tone']),
  EmojiEntry('👳‍♂️', ['man_wearing_turban']),
  EmojiEntry('👳🏿‍♀️', ['woman_wearing_turban_tone5', 'woman_wearing_turban_dark_skin_tone']),
  EmojiEntry('👳🏾‍♀️', ['woman_wearing_turban_tone4', 'woman_wearing_turban_medium_dark_skin_tone']),
  EmojiEntry('👳🏽‍♀️', ['woman_wearing_turban_tone3', 'woman_wearing_turban_medium_skin_tone']),
  EmojiEntry('👳🏼‍♀️', ['woman_wearing_turban_tone2', 'woman_wearing_turban_medium_light_skin_tone']),
  EmojiEntry('👳🏻‍♀️', ['woman_wearing_turban_tone1', 'woman_wearing_turban_light_skin_tone']),
  EmojiEntry('👳‍♀️', ['woman_wearing_turban']),
  EmojiEntry('💂🏿‍♂️', ['man_guard_tone5', 'man_guard_dark_skin_tone']),
  EmojiEntry('💂🏾‍♂️', ['man_guard_tone4', 'man_guard_medium_dark_skin_tone']),
  EmojiEntry('💂🏽‍♂️', ['man_guard_tone3', 'man_guard_medium_skin_tone']),
  EmojiEntry('💂🏼‍♂️', ['man_guard_tone2', 'man_guard_medium_light_skin_tone']),
  EmojiEntry('💂🏻‍♂️', ['man_guard_tone1', 'man_guard_light_skin_tone']),
  EmojiEntry('💂‍♂️', ['man_guard']),
  EmojiEntry('💂🏿‍♀️', ['woman_guard_tone5', 'woman_guard_dark_skin_tone']),
  EmojiEntry('💂🏾‍♀️', ['woman_guard_tone4', 'woman_guard_medium_dark_skin_tone']),
  EmojiEntry('💂🏽‍♀️', ['woman_guard_tone3', 'woman_guard_medium_skin_tone']),
  EmojiEntry('💂🏼‍♀️', ['woman_guard_tone2', 'woman_guard_medium_light_skin_tone']),
  EmojiEntry('💂🏻‍♀️', ['woman_guard_tone1', 'woman_guard_light_skin_tone']),
  EmojiEntry('💂‍♀️', ['woman_guard']),
  EmojiEntry('🕵🏿‍♂️', ['man_detective_tone5', 'man_detective_dark_skin_tone']),
  EmojiEntry('🕵🏾‍♂️', ['man_detective_tone4', 'man_detective_medium_dark_skin_tone']),
  EmojiEntry('🕵🏽‍♂️', ['man_detective_tone3', 'man_detective_medium_skin_tone']),
  EmojiEntry('🕵🏼‍♂️', ['man_detective_tone2', 'man_detective_medium_light_skin_tone']),
  EmojiEntry('🕵🏻‍♂️', ['man_detective_tone1', 'man_detective_light_skin_tone']),
  EmojiEntry('🕵️‍♂️', ['man_detective']),
  EmojiEntry('🕵🏿‍♀️', ['woman_detective_tone5', 'woman_detective_dark_skin_tone']),
  EmojiEntry('🕵🏾‍♀️', ['woman_detective_tone4', 'woman_detective_medium_dark_skin_tone']),
  EmojiEntry('🕵🏽‍♀️', ['woman_detective_tone3', 'woman_detective_medium_skin_tone']),
  EmojiEntry('🕵🏼‍♀️', ['woman_detective_tone2', 'woman_detective_medium_light_skin_tone']),
  EmojiEntry('🕵🏻‍♀️', ['woman_detective_tone1', 'woman_detective_light_skin_tone']),
  EmojiEntry('🕵️‍♀️', ['woman_detective']),
  EmojiEntry('👷🏿‍♂️', ['man_construction_worker_tone5', 'man_construction_worker_dark_skin_tone']),
  EmojiEntry('👷🏾‍♂️', ['man_construction_worker_tone4', 'man_construction_worker_medium_dark_skin_tone']),
  EmojiEntry('👷🏽‍♂️', ['man_construction_worker_tone3', 'man_construction_worker_medium_skin_tone']),
  EmojiEntry('👷🏼‍♂️', ['man_construction_worker_tone2', 'man_construction_worker_medium_light_skin_tone']),
  EmojiEntry('👷🏻‍♂️', ['man_construction_worker_tone1', 'man_construction_worker_light_skin_tone']),
  EmojiEntry('👷‍♂️', ['man_construction_worker']),
  EmojiEntry('👷🏿‍♀️', ['woman_construction_worker_tone5', 'woman_construction_worker_dark_skin_tone']),
  EmojiEntry('👷🏾‍♀️', ['woman_construction_worker_tone4', 'woman_construction_worker_medium_dark_skin_tone']),
  EmojiEntry('👷🏽‍♀️', ['woman_construction_worker_tone3', 'woman_construction_worker_medium_skin_tone']),
  EmojiEntry('👷🏼‍♀️', ['woman_construction_worker_tone2', 'woman_construction_worker_medium_light_skin_tone']),
  EmojiEntry('👷🏻‍♀️', ['woman_construction_worker_tone1', 'woman_construction_worker_light_skin_tone']),
  EmojiEntry('👷‍♀️', ['woman_construction_worker']),
  EmojiEntry('👮🏿‍♂️', ['man_police_officer_tone5', 'man_police_officer_dark_skin_tone']),
  EmojiEntry('👮🏾‍♂️', ['man_police_officer_tone4', 'man_police_officer_medium_dark_skin_tone']),
  EmojiEntry('👮🏽‍♂️', ['man_police_officer_tone3', 'man_police_officer_medium_skin_tone']),
  EmojiEntry('👮🏼‍♂️', ['man_police_officer_tone2', 'man_police_officer_medium_light_skin_tone']),
  EmojiEntry('👮🏻‍♂️', ['man_police_officer_tone1', 'man_police_officer_light_skin_tone']),
  EmojiEntry('👮‍♂️', ['man_police_officer']),
  EmojiEntry('👮🏿‍♀️', ['woman_police_officer_tone5', 'woman_police_officer_dark_skin_tone']),
  EmojiEntry('👮🏾‍♀️', ['woman_police_officer_tone4', 'woman_police_officer_medium_dark_skin_tone']),
  EmojiEntry('👮🏽‍♀️', ['woman_police_officer_tone3', 'woman_police_officer_medium_skin_tone']),
  EmojiEntry('👮🏼‍♀️', ['woman_police_officer_tone2', 'woman_police_officer_medium_light_skin_tone']),
  EmojiEntry('👮🏻‍♀️', ['woman_police_officer_tone1', 'woman_police_officer_light_skin_tone']),
  EmojiEntry('👮‍♀️', ['woman_police_officer']),
  EmojiEntry('👨🏿‍💻', ['man_technologist_tone5', 'man_technologist_dark_skin_tone']),
  EmojiEntry('👨🏾‍💻', ['man_technologist_tone4', 'man_technologist_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍💻', ['man_technologist_tone3', 'man_technologist_medium_skin_tone']),
  EmojiEntry('👨🏼‍💻', ['man_technologist_tone2', 'man_technologist_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍💻', ['man_technologist_tone1', 'man_technologist_light_skin_tone']),
  EmojiEntry('👨‍💻', ['man_technologist']),
  EmojiEntry('👩🏿‍💻', ['woman_technologist_tone5', 'woman_technologist_dark_skin_tone']),
  EmojiEntry('👩🏾‍💻', ['woman_technologist_tone4', 'woman_technologist_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍💻', ['woman_technologist_tone3', 'woman_technologist_medium_skin_tone']),
  EmojiEntry('👩🏼‍💻', ['woman_technologist_tone2', 'woman_technologist_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍💻', ['woman_technologist_tone1', 'woman_technologist_light_skin_tone']),
  EmojiEntry('👩‍💻', ['woman_technologist']),
  EmojiEntry('👨🏿‍🏫', ['man_teacher_tone5', 'man_teacher_dark_skin_tone']),
  EmojiEntry('👨🏾‍🏫', ['man_teacher_tone4', 'man_teacher_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🏫', ['man_teacher_tone3', 'man_teacher_medium_skin_tone']),
  EmojiEntry('👨🏼‍🏫', ['man_teacher_tone2', 'man_teacher_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🏫', ['man_teacher_tone1', 'man_teacher_light_skin_tone']),
  EmojiEntry('👨‍🏫', ['man_teacher']),
  EmojiEntry('👩🏿‍🏫', ['woman_teacher_tone5', 'woman_teacher_dark_skin_tone']),
  EmojiEntry('👩🏾‍🏫', ['woman_teacher_tone4', 'woman_teacher_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🏫', ['woman_teacher_tone3', 'woman_teacher_medium_skin_tone']),
  EmojiEntry('👩🏼‍🏫', ['woman_teacher_tone2', 'woman_teacher_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🏫', ['woman_teacher_tone1', 'woman_teacher_light_skin_tone']),
  EmojiEntry('👩‍🏫', ['woman_teacher']),
  EmojiEntry('👨🏿‍🎓', ['man_student_tone5', 'man_student_dark_skin_tone']),
  EmojiEntry('👨🏾‍🎓', ['man_student_tone4', 'man_student_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🎓', ['man_student_tone3', 'man_student_medium_skin_tone']),
  EmojiEntry('👨🏼‍🎓', ['man_student_tone2', 'man_student_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🎓', ['man_student_tone1', 'man_student_light_skin_tone']),
  EmojiEntry('👨‍🎓', ['man_student']),
  EmojiEntry('👩🏿‍🎓', ['woman_student_tone5', 'woman_student_dark_skin_tone']),
  EmojiEntry('👩🏾‍🎓', ['woman_student_tone4', 'woman_student_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🎓', ['woman_student_tone3', 'woman_student_medium_skin_tone']),
  EmojiEntry('👩🏼‍🎓', ['woman_student_tone2', 'woman_student_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🎓', ['woman_student_tone1', 'woman_student_light_skin_tone']),
  EmojiEntry('👩‍🎓', ['woman_student']),
  EmojiEntry('👨🏿‍🎤', ['man_singer_tone5', 'man_singer_dark_skin_tone']),
  EmojiEntry('👨🏾‍🎤', ['man_singer_tone4', 'man_singer_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🎤', ['man_singer_tone3', 'man_singer_medium_skin_tone']),
  EmojiEntry('👨🏼‍🎤', ['man_singer_tone2', 'man_singer_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🎤', ['man_singer_tone1', 'man_singer_light_skin_tone']),
  EmojiEntry('👨‍🎤', ['man_singer']),
  EmojiEntry('👩🏿‍🎤', ['woman_singer_tone5', 'woman_singer_dark_skin_tone']),
  EmojiEntry('👩🏾‍🎤', ['woman_singer_tone4', 'woman_singer_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🎤', ['woman_singer_tone3', 'woman_singer_medium_skin_tone']),
  EmojiEntry('👩🏼‍🎤', ['woman_singer_tone2', 'woman_singer_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🎤', ['woman_singer_tone1', 'woman_singer_light_skin_tone']),
  EmojiEntry('👩‍🎤', ['woman_singer']),
  EmojiEntry('👨🏿‍🔬', ['man_scientist_tone5', 'man_scientist_dark_skin_tone']),
  EmojiEntry('👨🏾‍🔬', ['man_scientist_tone4', 'man_scientist_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🔬', ['man_scientist_tone3', 'man_scientist_medium_skin_tone']),
  EmojiEntry('👨🏼‍🔬', ['man_scientist_tone2', 'man_scientist_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🔬', ['man_scientist_tone1', 'man_scientist_light_skin_tone']),
  EmojiEntry('👨‍🔬', ['man_scientist']),
  EmojiEntry('👩🏿‍🔬', ['woman_scientist_tone5', 'woman_scientist_dark_skin_tone']),
  EmojiEntry('👩🏾‍🔬', ['woman_scientist_tone4', 'woman_scientist_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🔬', ['woman_scientist_tone3', 'woman_scientist_medium_skin_tone']),
  EmojiEntry('👩🏼‍🔬', ['woman_scientist_tone2', 'woman_scientist_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🔬', ['woman_scientist_tone1', 'woman_scientist_light_skin_tone']),
  EmojiEntry('👩‍🔬', ['woman_scientist']),
  EmojiEntry('👨🏿‍💼', ['man_office_worker_tone5', 'man_office_worker_dark_skin_tone']),
  EmojiEntry('👨🏾‍💼', ['man_office_worker_tone4', 'man_office_worker_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍💼', ['man_office_worker_tone3', 'man_office_worker_medium_skin_tone']),
  EmojiEntry('👨🏼‍💼', ['man_office_worker_tone2', 'man_office_worker_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍💼', ['man_office_worker_tone1', 'man_office_worker_light_skin_tone']),
  EmojiEntry('👨‍💼', ['man_office_worker']),
  EmojiEntry('👩🏿‍💼', ['woman_office_worker_tone5', 'woman_office_worker_dark_skin_tone']),
  EmojiEntry('👩🏾‍💼', ['woman_office_worker_tone4', 'woman_office_worker_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍💼', ['woman_office_worker_tone3', 'woman_office_worker_medium_skin_tone']),
  EmojiEntry('👩🏼‍💼', ['woman_office_worker_tone2', 'woman_office_worker_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍💼', ['woman_office_worker_tone1', 'woman_office_worker_light_skin_tone']),
  EmojiEntry('👩‍💼', ['woman_office_worker']),
  EmojiEntry('👨🏿‍🔧', ['man_mechanic_tone5', 'man_mechanic_dark_skin_tone']),
  EmojiEntry('👨🏾‍🔧', ['man_mechanic_tone4', 'man_mechanic_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🔧', ['man_mechanic_tone3', 'man_mechanic_medium_skin_tone']),
  EmojiEntry('👨🏼‍🔧', ['man_mechanic_tone2', 'man_mechanic_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🔧', ['man_mechanic_tone1', 'man_mechanic_light_skin_tone']),
  EmojiEntry('👨‍🔧', ['man_mechanic']),
  EmojiEntry('👩🏿‍🔧', ['woman_mechanic_tone5', 'woman_mechanic_dark_skin_tone']),
  EmojiEntry('👩🏾‍🔧', ['woman_mechanic_tone4', 'woman_mechanic_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🔧', ['woman_mechanic_tone3', 'woman_mechanic_medium_skin_tone']),
  EmojiEntry('👩🏼‍🔧', ['woman_mechanic_tone2', 'woman_mechanic_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🔧', ['woman_mechanic_tone1', 'woman_mechanic_light_skin_tone']),
  EmojiEntry('👩‍🔧', ['woman_mechanic']),
  EmojiEntry('👨🏿‍⚕️', ['man_health_worker_tone5', 'man_health_worker_dark_skin_tone']),
  EmojiEntry('👨🏾‍⚕️', ['man_health_worker_tone4', 'man_health_worker_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍⚕️', ['man_health_worker_tone3', 'man_health_worker_medium_skin_tone']),
  EmojiEntry('👨🏼‍⚕️', ['man_health_worker_tone2', 'man_health_worker_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍⚕️', ['man_health_worker_tone1', 'man_health_worker_light_skin_tone']),
  EmojiEntry('👨‍⚕️', ['man_health_worker']),
  EmojiEntry('👩🏿‍⚕️', ['woman_health_worker_tone5', 'woman_health_worker_dark_skin_tone']),
  EmojiEntry('👩🏾‍⚕️', ['woman_health_worker_tone4', 'woman_health_worker_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍⚕️', ['woman_health_worker_tone3', 'woman_health_worker_medium_skin_tone']),
  EmojiEntry('👩🏼‍⚕️', ['woman_health_worker_tone2', 'woman_health_worker_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍⚕️', ['woman_health_worker_tone1', 'woman_health_worker_light_skin_tone']),
  EmojiEntry('👩‍⚕️', ['woman_health_worker']),
  EmojiEntry('👨🏿‍🏭', ['man_factory_worker_tone5', 'man_factory_worker_dark_skin_tone']),
  EmojiEntry('👨🏾‍🏭', ['man_factory_worker_tone4', 'man_factory_worker_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🏭', ['man_factory_worker_tone3', 'man_factory_worker_medium_skin_tone']),
  EmojiEntry('👨🏼‍🏭', ['man_factory_worker_tone2', 'man_factory_worker_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🏭', ['man_factory_worker_tone1', 'man_factory_worker_light_skin_tone']),
  EmojiEntry('👨‍🏭', ['man_factory_worker']),
  EmojiEntry('👩🏿‍🏭', ['woman_factory_worker_tone5', 'woman_factory_worker_dark_skin_tone']),
  EmojiEntry('👩🏾‍🏭', ['woman_factory_worker_tone4', 'woman_factory_worker_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🏭', ['woman_factory_worker_tone3', 'woman_factory_worker_medium_skin_tone']),
  EmojiEntry('👩🏼‍🏭', ['woman_factory_worker_tone2', 'woman_factory_worker_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🏭', ['woman_factory_worker_tone1', 'woman_factory_worker_light_skin_tone']),
  EmojiEntry('👩‍🏭', ['woman_factory_worker']),
  EmojiEntry('👨🏿‍🍳', ['man_cook_tone5', 'man_cook_dark_skin_tone']),
  EmojiEntry('👨🏾‍🍳', ['man_cook_tone4', 'man_cook_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🍳', ['man_cook_tone3', 'man_cook_medium_skin_tone']),
  EmojiEntry('👨🏼‍🍳', ['man_cook_tone2', 'man_cook_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🍳', ['man_cook_tone1', 'man_cook_light_skin_tone']),
  EmojiEntry('👨‍🍳', ['man_cook']),
  EmojiEntry('👩🏿‍🍳', ['woman_cook_tone5', 'woman_cook_dark_skin_tone']),
  EmojiEntry('👩🏾‍🍳', ['woman_cook_tone4', 'woman_cook_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🍳', ['woman_cook_tone3', 'woman_cook_medium_skin_tone']),
  EmojiEntry('👩🏼‍🍳', ['woman_cook_tone2', 'woman_cook_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🍳', ['woman_cook_tone1', 'woman_cook_light_skin_tone']),
  EmojiEntry('👩‍🍳', ['woman_cook']),
  EmojiEntry('👨🏿‍🌾', ['man_farmer_tone5', 'man_farmer_dark_skin_tone']),
  EmojiEntry('👨🏾‍🌾', ['man_farmer_tone4', 'man_farmer_medium_dark_skin_tone']),
  EmojiEntry('👨🏽‍🌾', ['man_farmer_tone3', 'man_farmer_medium_skin_tone']),
  EmojiEntry('👨🏼‍🌾', ['man_farmer_tone2', 'man_farmer_medium_light_skin_tone']),
  EmojiEntry('👨🏻‍🌾', ['man_farmer_tone1', 'man_farmer_light_skin_tone']),
  EmojiEntry('👨‍🌾', ['man_farmer']),
  EmojiEntry('👩🏿‍🌾', ['woman_farmer_tone5', 'woman_farmer_dark_skin_tone']),
  EmojiEntry('👩🏾‍🌾', ['woman_farmer_tone4', 'woman_farmer_medium_dark_skin_tone']),
  EmojiEntry('👩🏽‍🌾', ['woman_farmer_tone3', 'woman_farmer_medium_skin_tone']),
  EmojiEntry('👩🏼‍🌾', ['woman_farmer_tone2', 'woman_farmer_medium_light_skin_tone']),
  EmojiEntry('👩🏻‍🌾', ['woman_farmer_tone1', 'woman_farmer_light_skin_tone']),
  EmojiEntry('👩‍🌾', ['woman_farmer']),
  EmojiEntry('🕴🏻', ['man_in_business_suit_levitating_tone1', 'man_in_business_suit_levitating_light_skin_tone']),
  EmojiEntry('🕴🏼', ['man_in_business_suit_levitating_tone2', 'man_in_business_suit_levitating_medium_light_skin_tone']),
  EmojiEntry('🕴🏽', ['man_in_business_suit_levitating_tone3', 'man_in_business_suit_levitating_medium_skin_tone']),
  EmojiEntry('🕴🏾', ['man_in_business_suit_levitating_tone4', 'man_in_business_suit_levitating_medium_dark_skin_tone']),
  EmojiEntry('🕴🏿', ['man_in_business_suit_levitating_tone5', 'man_in_business_suit_levitating_dark_skin_tone']),
  EmojiEntry('🛌🏻', ['person_in_bed_tone1', 'person_in_bed_light_skin_tone']),
  EmojiEntry('🛌🏼', ['person_in_bed_tone2', 'person_in_bed_medium_light_skin_tone']),
  EmojiEntry('🛌🏽', ['person_in_bed_tone3', 'person_in_bed_medium_skin_tone']),
  EmojiEntry('🛌🏾', ['person_in_bed_tone4', 'person_in_bed_medium_dark_skin_tone']),
  EmojiEntry('🛌🏿', ['person_in_bed_tone5', 'person_in_bed_dark_skin_tone']),
  EmojiEntry('👨‍👦', ['family_man_boy']),
  EmojiEntry('👨‍👦‍👦', ['family_man_boy_boy']),
  EmojiEntry('👨‍👧', ['family_man_girl']),
  EmojiEntry('👨‍👧‍👦', ['family_man_girl_boy']),
  EmojiEntry('👩‍👦', ['family_woman_boy']),
  EmojiEntry('👩‍👦‍👦', ['family_woman_boy_boy']),
  EmojiEntry('👩‍👧', ['family_woman_girl']),
  EmojiEntry('👩‍👧‍👦', ['family_woman_girl_boy']),
  EmojiEntry('👩‍👧‍👧', ['family_woman_girl_girl']),
  EmojiEntry('👨‍⚖️', ['man_judge']),
  EmojiEntry('👨🏻‍⚖️', ['man_judge_tone1', 'man_judge_light_skin_tone']),
  EmojiEntry('👨🏼‍⚖️', ['man_judge_tone2', 'man_judge_medium_light_skin_tone']),
  EmojiEntry('👨🏽‍⚖️', ['man_judge_tone3', 'man_judge_medium_skin_tone']),
  EmojiEntry('👨🏾‍⚖️', ['man_judge_tone4', 'man_judge_medium_dark_skin_tone']),
  EmojiEntry('👨🏿‍⚖️', ['man_judge_tone5', 'man_judge_dark_skin_tone']),
  EmojiEntry('👩‍⚖️', ['woman_judge']),
  EmojiEntry('👩🏻‍⚖️', ['woman_judge_tone1', 'woman_judge_light_skin_tone']),
  EmojiEntry('👩🏼‍⚖️', ['woman_judge_tone2', 'woman_judge_medium_light_skin_tone']),
  EmojiEntry('👩🏽‍⚖️', ['woman_judge_tone3', 'woman_judge_medium_skin_tone']),
  EmojiEntry('👩🏾‍⚖️', ['woman_judge_tone4', 'woman_judge_medium_dark_skin_tone']),
  EmojiEntry('👩🏿‍⚖️', ['woman_judge_tone5', 'woman_judge_dark_skin_tone']),
  EmojiEntry('👨‍✈️', ['man_pilot']),
  EmojiEntry('👨🏻‍✈️', ['man_pilot_tone1', 'man_pilot_light_skin_tone']),
  EmojiEntry('👨🏼‍✈️', ['man_pilot_tone2', 'man_pilot_medium_light_skin_tone']),
  EmojiEntry('👨🏽‍✈️', ['man_pilot_tone3', 'man_pilot_medium_skin_tone']),
  EmojiEntry('👨🏾‍✈️', ['man_pilot_tone4', 'man_pilot_medium_dark_skin_tone']),
  EmojiEntry('👨🏿‍✈️', ['man_pilot_tone5', 'man_pilot_dark_skin_tone']),
  EmojiEntry('👩‍✈️', ['woman_pilot']),
  EmojiEntry('👩🏻‍✈️', ['woman_pilot_tone1', 'woman_pilot_light_skin_tone']),
  EmojiEntry('👩🏼‍✈️', ['woman_pilot_tone2', 'woman_pilot_medium_light_skin_tone']),
  EmojiEntry('👩🏽‍✈️', ['woman_pilot_tone3', 'woman_pilot_medium_skin_tone']),
  EmojiEntry('👩🏾‍✈️', ['woman_pilot_tone4', 'woman_pilot_medium_dark_skin_tone']),
  EmojiEntry('👩🏿‍✈️', ['woman_pilot_tone5', 'woman_pilot_dark_skin_tone']),
  EmojiEntry('👨‍🎨', ['man_artist']),
  EmojiEntry('👨🏻‍🎨', ['man_artist_tone1', 'man_artist_light_skin_tone']),
  EmojiEntry('👨🏼‍🎨', ['man_artist_tone2', 'man_artist_medium_light_skin_tone']),
  EmojiEntry('👨🏽‍🎨', ['man_artist_tone3', 'man_artist_medium_skin_tone']),
  EmojiEntry('👨🏾‍🎨', ['man_artist_tone4', 'man_artist_medium_dark_skin_tone']),
  EmojiEntry('👨🏿‍🎨', ['man_artist_tone5', 'man_artist_dark_skin_tone']),
  EmojiEntry('👩‍🎨', ['woman_artist']),
  EmojiEntry('👩🏻‍🎨', ['woman_artist_tone1', 'woman_artist_light_skin_tone']),
  EmojiEntry('👩🏼‍🎨', ['woman_artist_tone2', 'woman_artist_medium_light_skin_tone']),
  EmojiEntry('👩🏽‍🎨', ['woman_artist_tone3', 'woman_artist_medium_skin_tone']),
  EmojiEntry('👩🏾‍🎨', ['woman_artist_tone4', 'woman_artist_medium_dark_skin_tone']),
  EmojiEntry('👩🏿‍🎨', ['woman_artist_tone5', 'woman_artist_dark_skin_tone']),
  EmojiEntry('👨‍🚀', ['man_astronaut']),
  EmojiEntry('👨🏻‍🚀', ['man_astronaut_tone1', 'man_astronaut_light_skin_tone']),
  EmojiEntry('👨🏼‍🚀', ['man_astronaut_tone2', 'man_astronaut_medium_light_skin_tone']),
  EmojiEntry('👨🏽‍🚀', ['man_astronaut_tone3', 'man_astronaut_medium_skin_tone']),
  EmojiEntry('👨🏾‍🚀', ['man_astronaut_tone4', 'man_astronaut_medium_dark_skin_tone']),
  EmojiEntry('👨🏿‍🚀', ['man_astronaut_tone5', 'man_astronaut_dark_skin_tone']),
  EmojiEntry('👩‍🚀', ['woman_astronaut']),
  EmojiEntry('👩🏻‍🚀', ['woman_astronaut_tone1', 'woman_astronaut_light_skin_tone']),
  EmojiEntry('👩🏼‍🚀', ['woman_astronaut_tone2', 'woman_astronaut_medium_light_skin_tone']),
  EmojiEntry('👩🏽‍🚀', ['woman_astronaut_tone3', 'woman_astronaut_medium_skin_tone']),
  EmojiEntry('👩🏾‍🚀', ['woman_astronaut_tone4', 'woman_astronaut_medium_dark_skin_tone']),
  EmojiEntry('👩🏿‍🚀', ['woman_astronaut_tone5', 'woman_astronaut_dark_skin_tone']),
  EmojiEntry('👨‍🚒', ['man_firefighter']),
  EmojiEntry('👨🏻‍🚒', ['man_firefighter_tone1', 'man_firefighter_light_skin_tone']),
  EmojiEntry('👨🏼‍🚒', ['man_firefighter_tone2', 'man_firefighter_medium_light_skin_tone']),
  EmojiEntry('👨🏽‍🚒', ['man_firefighter_tone3', 'man_firefighter_medium_skin_tone']),
  EmojiEntry('👨🏾‍🚒', ['man_firefighter_tone4', 'man_firefighter_medium_dark_skin_tone']),
  EmojiEntry('👨🏿‍🚒', ['man_firefighter_tone5', 'man_firefighter_dark_skin_tone']),
  EmojiEntry('👩‍🚒', ['woman_firefighter']),
  EmojiEntry('👩🏻‍🚒', ['woman_firefighter_tone1', 'woman_firefighter_light_skin_tone']),
  EmojiEntry('👩🏼‍🚒', ['woman_firefighter_tone2', 'woman_firefighter_medium_light_skin_tone']),
  EmojiEntry('👩🏽‍🚒', ['woman_firefighter_tone3', 'woman_firefighter_medium_skin_tone']),
  EmojiEntry('👩🏾‍🚒', ['woman_firefighter_tone4', 'woman_firefighter_medium_dark_skin_tone']),
  EmojiEntry('👩🏿‍🚒', ['woman_firefighter_tone5', 'woman_firefighter_dark_skin_tone']),
  EmojiEntry('♀️', ['female_sign']),
  EmojiEntry('♂️', ['male_sign']),
  EmojiEntry('⚕️', ['medical_symbol']),
  EmojiEntry('🇺🇳', ['united_nations']),
  EmojiEntry('🏂🏼', ['snowboarder_tone2', 'snowboarder_medium_light_skin_tone']),
  EmojiEntry('🏂🏽', ['snowboarder_tone3', 'snowboarder_medium_skin_tone']),
  EmojiEntry('🏂🏾', ['snowboarder_tone4', 'snowboarder_medium_dark_skin_tone']),
  EmojiEntry('🏂🏿', ['snowboarder_tone5', 'snowboarder_dark_skin_tone']),
  EmojiEntry('🏌🏻', ['person_golfing_tone1', 'person_golfing_light_skin_tone']),
  EmojiEntry('🏌🏼', ['person_golfing_tone2', 'person_golfing_medium_light_skin_tone']),
  EmojiEntry('🏌🏽', ['person_golfing_tone3', 'person_golfing_medium_skin_tone']),
  EmojiEntry('🏌🏾', ['person_golfing_tone4', 'person_golfing_medium_dark_skin_tone']),
  EmojiEntry('🏌🏿', ['person_golfing_tone5', 'person_golfing_dark_skin_tone']),
  EmojiEntry('👨‍👧‍👧', ['family_man_girl_girl']),
  EmojiEntry('👨‍👩‍👦', ['family_man_woman_boy']),
  EmojiEntry('👩‍❤️‍👨', ['couple_with_heart_woman_man']),
  EmojiEntry('👩‍❤️‍💋‍👨', ['kiss_woman_man']),
  EmojiEntry('🛷', ['sled']),
  EmojiEntry('🛸', ['flying_saucer']),
  EmojiEntry('🤟', ['love_you_gesture']),
  EmojiEntry('🤨', ['face_with_raised_eyebrow']),
  EmojiEntry('🤩', ['star_struck']),
  EmojiEntry('🤪', ['crazy_face']),
  EmojiEntry('🤫', ['shushing_face']),
  EmojiEntry('🤬', ['face_with_symbols_over_mouth']),
  EmojiEntry('🤭', ['face_with_hand_over_mouth']),
  EmojiEntry('🤮', ['face_vomiting']),
  EmojiEntry('🤯', ['exploding_head']),
  EmojiEntry('🤱', ['breast_feeding']),
  EmojiEntry('🤲', ['palms_up_together']),
  EmojiEntry('🥌', ['curling_stone']),
  EmojiEntry('🥟', ['dumpling']),
  EmojiEntry('🥠', ['fortune_cookie']),
  EmojiEntry('🥡', ['takeout_box']),
  EmojiEntry('🥢', ['chopsticks']),
  EmojiEntry('🥣', ['bowl_with_spoon']),
  EmojiEntry('🥤', ['cup_with_straw']),
  EmojiEntry('🥥', ['coconut']),
  EmojiEntry('🥦', ['broccoli']),
  EmojiEntry('🥧', ['pie']),
  EmojiEntry('🥨', ['pretzel']),
  EmojiEntry('🥩', ['cut_of_meat']),
  EmojiEntry('🥪', ['sandwich']),
  EmojiEntry('🥫', ['canned_food']),
  EmojiEntry('🦒', ['giraffe']),
  EmojiEntry('🦓', ['zebra']),
  EmojiEntry('🦔', ['hedgehog']),
  EmojiEntry('🦕', ['sauropod']),
  EmojiEntry('🦖', ['t_rex']),
  EmojiEntry('🦗', ['cricket']),
  EmojiEntry('🧐', ['face_with_monocle']),
  EmojiEntry('🧑', ['adult']),
  EmojiEntry('🧒', ['child']),
  EmojiEntry('🧓', ['older_adult']),
  EmojiEntry('🧔', ['bearded_person']),
  EmojiEntry('🧕', ['woman_with_headscarf']),
  EmojiEntry('🧖', ['person_in_steamy_room']),
  EmojiEntry('🧗', ['person_climbing']),
  EmojiEntry('🧘', ['person_in_lotus_position']),
  EmojiEntry('🧙', ['mage']),
  EmojiEntry('🧚', ['fairy']),
  EmojiEntry('🧛', ['vampire']),
  EmojiEntry('🧜', ['merperson']),
  EmojiEntry('🧝', ['elf']),
  EmojiEntry('🧞', ['genie']),
  EmojiEntry('🧟', ['zombie']),
  EmojiEntry('🧠', ['brain']),
  EmojiEntry('🧡', ['orange_heart']),
  EmojiEntry('🧢', ['billed_cap']),
  EmojiEntry('🧣', ['scarf']),
  EmojiEntry('🧤', ['gloves']),
  EmojiEntry('🧥', ['coat']),
  EmojiEntry('🧦', ['socks']),
  EmojiEntry('🏴󠁧󠁢󠁥󠁮󠁧󠁿', ['england']),
  EmojiEntry('🏴󠁧󠁢󠁳󠁣󠁴󠁿', ['scotland']),
  EmojiEntry('🏴󠁧󠁢󠁷󠁬󠁳󠁿', ['wales']),
  EmojiEntry('🤟🏻', ['love_you_gesture_tone1', 'love_you_gesture_light_skin_tone']),
  EmojiEntry('🤟🏼', ['love_you_gesture_tone2', 'love_you_gesture_medium_light_skin_tone']),
  EmojiEntry('🤟🏽', ['love_you_gesture_tone3', 'love_you_gesture_medium_skin_tone']),
  EmojiEntry('🤟🏾', ['love_you_gesture_tone4', 'love_you_gesture_medium_dark_skin_tone']),
  EmojiEntry('🤟🏿', ['love_you_gesture_tone5', 'love_you_gesture_dark_skin_tone']),
  EmojiEntry('🤱🏻', ['breast_feeding_tone1', 'breast_feeding_light_skin_tone']),
  EmojiEntry('🤱🏼', ['breast_feeding_tone2', 'breast_feeding_medium_light_skin_tone']),
  EmojiEntry('🤱🏽', ['breast_feeding_tone3', 'breast_feeding_medium_skin_tone']),
  EmojiEntry('🤱🏾', ['breast_feeding_tone4', 'breast_feeding_medium_dark_skin_tone']),
  EmojiEntry('🤱🏿', ['breast_feeding_tone5', 'breast_feeding_dark_skin_tone']),
  EmojiEntry('🤲🏻', ['palms_up_together_tone1', 'palms_up_together_light_skin_tone']),
  EmojiEntry('🤲🏼', ['palms_up_together_tone2', 'palms_up_together_medium_light_skin_tone']),
  EmojiEntry('🤲🏽', ['palms_up_together_tone3', 'palms_up_together_medium_skin_tone']),
  EmojiEntry('🤲🏾', ['palms_up_together_tone4', 'palms_up_together_medium_dark_skin_tone']),
  EmojiEntry('🤲🏿', ['palms_up_together_tone5', 'palms_up_together_dark_skin_tone']),
  EmojiEntry('🧑🏻', ['adult_tone1', 'adult_light_skin_tone']),
  EmojiEntry('🧑🏼', ['adult_tone2', 'adult_medium_light_skin_tone']),
  EmojiEntry('🧑🏽', ['adult_tone3', 'adult_medium_skin_tone']),
  EmojiEntry('🧑🏾', ['adult_tone4', 'adult_medium_dark_skin_tone']),
  EmojiEntry('🧑🏿', ['adult_tone5', 'adult_dark_skin_tone']),
  EmojiEntry('🧒🏻', ['child_tone1', 'child_light_skin_tone']),
  EmojiEntry('🧒🏼', ['child_tone2', 'child_medium_light_skin_tone']),
  EmojiEntry('🧒🏽', ['child_tone3', 'child_medium_skin_tone']),
  EmojiEntry('🧒🏾', ['child_tone4', 'child_medium_dark_skin_tone']),
  EmojiEntry('🧒🏿', ['child_tone5', 'child_dark_skin_tone']),
  EmojiEntry('🧓🏻', ['older_adult_tone1', 'older_adult_light_skin_tone']),
  EmojiEntry('🧓🏼', ['older_adult_tone2', 'older_adult_medium_light_skin_tone']),
  EmojiEntry('🧓🏽', ['older_adult_tone3', 'older_adult_medium_skin_tone']),
  EmojiEntry('🧓🏾', ['older_adult_tone4', 'older_adult_medium_dark_skin_tone']),
  EmojiEntry('🧓🏿', ['older_adult_tone5', 'older_adult_dark_skin_tone']),
  EmojiEntry('🧔🏻', ['bearded_person_tone1', 'bearded_person_light_skin_tone']),
  EmojiEntry('🧔🏼', ['bearded_person_tone2', 'bearded_person_medium_light_skin_tone']),
  EmojiEntry('🧔🏽', ['bearded_person_tone3', 'bearded_person_medium_skin_tone']),
  EmojiEntry('🧔🏾', ['bearded_person_tone4', 'bearded_person_medium_dark_skin_tone']),
  EmojiEntry('🧔🏿', ['bearded_person_tone5', 'bearded_person_dark_skin_tone']),
  EmojiEntry('🧕🏻', ['woman_with_headscarf_tone1', 'woman_with_headscarf_light_skin_tone']),
  EmojiEntry('🧕🏼', ['woman_with_headscarf_tone2', 'woman_with_headscarf_medium_light_skin_tone']),
  EmojiEntry('🧕🏽', ['woman_with_headscarf_tone3', 'woman_with_headscarf_medium_skin_tone']),
  EmojiEntry('🧕🏾', ['woman_with_headscarf_tone4', 'woman_with_headscarf_medium_dark_skin_tone']),
  EmojiEntry('🧕🏿', ['woman_with_headscarf_tone5', 'woman_with_headscarf_dark_skin_tone']),
  EmojiEntry('🧖🏻', ['person_in_steamy_room_tone1', 'person_in_steamy_room_light_skin_tone']),
  EmojiEntry('🧖🏼', ['person_in_steamy_room_tone2', 'person_in_steamy_room_medium_light_skin_tone']),
  EmojiEntry('🧖🏽', ['person_in_steamy_room_tone3', 'person_in_steamy_room_medium_skin_tone']),
  EmojiEntry('🧖🏾', ['person_in_steamy_room_tone4', 'person_in_steamy_room_medium_dark_skin_tone']),
  EmojiEntry('🧖🏿', ['person_in_steamy_room_tone5', 'person_in_steamy_room_dark_skin_tone']),
  EmojiEntry('🧗🏻', ['person_climbing_tone1', 'person_climbing_light_skin_tone']),
  EmojiEntry('🧗🏼', ['person_climbing_tone2', 'person_climbing_medium_light_skin_tone']),
  EmojiEntry('🧗🏽', ['person_climbing_tone3', 'person_climbing_medium_skin_tone']),
  EmojiEntry('🧗🏾', ['person_climbing_tone4', 'person_climbing_medium_dark_skin_tone']),
  EmojiEntry('🧗🏿', ['person_climbing_tone5', 'person_climbing_dark_skin_tone']),
  EmojiEntry('🧘🏻', ['person_in_lotus_position_tone1', 'person_in_lotus_position_light_skin_tone']),
  EmojiEntry('🧘🏼', ['person_in_lotus_position_tone2', 'person_in_lotus_position_medium_light_skin_tone']),
  EmojiEntry('🧘🏽', ['person_in_lotus_position_tone3', 'person_in_lotus_position_medium_skin_tone']),
  EmojiEntry('🧘🏾', ['person_in_lotus_position_tone4', 'person_in_lotus_position_medium_dark_skin_tone']),
  EmojiEntry('🧘🏿', ['person_in_lotus_position_tone5', 'person_in_lotus_position_dark_skin_tone']),
  EmojiEntry('🧙🏻', ['mage_tone1', 'mage_light_skin_tone']),
  EmojiEntry('🧙🏼', ['mage_tone2', 'mage_medium_light_skin_tone']),
  EmojiEntry('🧙🏽', ['mage_tone3', 'mage_medium_skin_tone']),
  EmojiEntry('🧙🏾', ['mage_tone4', 'mage_medium_dark_skin_tone']),
  EmojiEntry('🧙🏿', ['mage_tone5', 'mage_dark_skin_tone']),
  EmojiEntry('🧚🏻', ['fairy_tone1', 'fairy_light_skin_tone']),
  EmojiEntry('🧚🏼', ['fairy_tone2', 'fairy_medium_light_skin_tone']),
  EmojiEntry('🧚🏽', ['fairy_tone3', 'fairy_medium_skin_tone']),
  EmojiEntry('🧚🏾', ['fairy_tone4', 'fairy_medium_dark_skin_tone']),
  EmojiEntry('🧚🏿', ['fairy_tone5', 'fairy_dark_skin_tone']),
  EmojiEntry('🧛🏻', ['vampire_tone1', 'vampire_light_skin_tone']),
  EmojiEntry('🧛🏼', ['vampire_tone2', 'vampire_medium_light_skin_tone']),
  EmojiEntry('🧛🏽', ['vampire_tone3', 'vampire_medium_skin_tone']),
  EmojiEntry('🧛🏾', ['vampire_tone4', 'vampire_medium_dark_skin_tone']),
  EmojiEntry('🧛🏿', ['vampire_tone5', 'vampire_dark_skin_tone']),
  EmojiEntry('🧜🏻', ['merperson_tone1', 'merperson_light_skin_tone']),
  EmojiEntry('🧜🏼', ['merperson_tone2', 'merperson_medium_light_skin_tone']),
  EmojiEntry('🧜🏽', ['merperson_tone3', 'merperson_medium_skin_tone']),
  EmojiEntry('🧜🏾', ['merperson_tone4', 'merperson_medium_dark_skin_tone']),
  EmojiEntry('🧜🏿', ['merperson_tone5', 'merperson_dark_skin_tone']),
  EmojiEntry('🧝🏻', ['elf_tone1', 'elf_light_skin_tone']),
  EmojiEntry('🧝🏼', ['elf_tone2', 'elf_medium_light_skin_tone']),
  EmojiEntry('🧝🏽', ['elf_tone3', 'elf_medium_skin_tone']),
  EmojiEntry('🧝🏾', ['elf_tone4', 'elf_medium_dark_skin_tone']),
  EmojiEntry('🧝🏿', ['elf_tone5', 'elf_dark_skin_tone']),
  EmojiEntry('🧙‍♀️', ['woman_mage']),
  EmojiEntry('🧙‍♂️', ['man_mage']),
  EmojiEntry('🧙🏻‍♀️', ['woman_mage_tone1', 'woman_mage_light_skin_tone']),
  EmojiEntry('🧙🏻‍♂️', ['man_mage_tone1', 'man_mage_light_skin_tone']),
  EmojiEntry('🧙🏼‍♀️', ['woman_mage_tone2', 'woman_mage_medium_light_skin_tone']),
  EmojiEntry('🧙🏼‍♂️', ['man_mage_tone2', 'man_mage_medium_light_skin_tone']),
  EmojiEntry('🧙🏽‍♀️', ['woman_mage_tone3', 'woman_mage_medium_skin_tone']),
  EmojiEntry('🧙🏽‍♂️', ['man_mage_tone3', 'man_mage_medium_skin_tone']),
  EmojiEntry('🧙🏾‍♀️', ['woman_mage_tone4', 'woman_mage_medium_dark_skin_tone']),
  EmojiEntry('🧙🏾‍♂️', ['man_mage_tone4', 'man_mage_medium_dark_skin_tone']),
  EmojiEntry('🧙🏿‍♀️', ['woman_mage_tone5', 'woman_mage_dark_skin_tone']),
  EmojiEntry('🧙🏿‍♂️', ['man_mage_tone5', 'man_mage_dark_skin_tone']),
  EmojiEntry('🧚‍♀️', ['woman_fairy']),
  EmojiEntry('🧚‍♂️', ['man_fairy']),
  EmojiEntry('🧚🏻‍♀️', ['woman_fairy_tone1', 'woman_fairy_light_skin_tone']),
  EmojiEntry('🧚🏻‍♂️', ['man_fairy_tone1', 'man_fairy_light_skin_tone']),
  EmojiEntry('🧚🏼‍♀️', ['woman_fairy_tone2', 'woman_fairy_medium_light_skin_tone']),
  EmojiEntry('🧚🏼‍♂️', ['man_fairy_tone2', 'man_fairy_medium_light_skin_tone']),
  EmojiEntry('🧚🏽‍♀️', ['woman_fairy_tone3', 'woman_fairy_medium_skin_tone']),
  EmojiEntry('🧚🏽‍♂️', ['man_fairy_tone3', 'man_fairy_medium_skin_tone']),
  EmojiEntry('🧚🏾‍♀️', ['woman_fairy_tone4', 'woman_fairy_medium_dark_skin_tone']),
  EmojiEntry('🧚🏾‍♂️', ['man_fairy_tone4', 'man_fairy_medium_dark_skin_tone']),
  EmojiEntry('🧚🏿‍♀️', ['woman_fairy_tone5', 'woman_fairy_dark_skin_tone']),
  EmojiEntry('🧚🏿‍♂️', ['man_fairy_tone5', 'man_fairy_dark_skin_tone']),
  EmojiEntry('🧛‍♀️', ['woman_vampire']),
  EmojiEntry('🧛‍♂️', ['man_vampire']),
  EmojiEntry('🧛🏻‍♀️', ['woman_vampire_tone1', 'woman_vampire_light_skin_tone']),
  EmojiEntry('🧛🏻‍♂️', ['man_vampire_tone1', 'man_vampire_light_skin_tone']),
  EmojiEntry('🧛🏼‍♀️', ['woman_vampire_tone2', 'woman_vampire_medium_light_skin_tone']),
  EmojiEntry('🧛🏼‍♂️', ['man_vampire_tone2', 'man_vampire_medium_light_skin_tone']),
  EmojiEntry('🧛🏽‍♀️', ['woman_vampire_tone3', 'woman_vampire_medium_skin_tone']),
  EmojiEntry('🧛🏽‍♂️', ['man_vampire_tone3', 'man_vampire_medium_skin_tone']),
  EmojiEntry('🧛🏾‍♀️', ['woman_vampire_tone4', 'woman_vampire_medium_dark_skin_tone']),
  EmojiEntry('🧛🏾‍♂️', ['man_vampire_tone4', 'man_vampire_medium_dark_skin_tone']),
  EmojiEntry('🧛🏿‍♀️', ['woman_vampire_tone5', 'woman_vampire_dark_skin_tone']),
  EmojiEntry('🧛🏿‍♂️', ['man_vampire_tone5', 'man_vampire_dark_skin_tone']),
  EmojiEntry('🧜‍♀️', ['mermaid']),
  EmojiEntry('🧜‍♂️', ['merman']),
  EmojiEntry('🧜🏻‍♀️', ['mermaid_tone1', 'mermaid_light_skin_tone']),
  EmojiEntry('🧜🏻‍♂️', ['merman_tone1', 'merman_light_skin_tone']),
  EmojiEntry('🧜🏼‍♀️', ['mermaid_tone2', 'mermaid_medium_light_skin_tone']),
  EmojiEntry('🧜🏼‍♂️', ['merman_tone2', 'merman_medium_light_skin_tone']),
  EmojiEntry('🧜🏽‍♀️', ['mermaid_tone3', 'mermaid_medium_skin_tone']),
  EmojiEntry('🧜🏽‍♂️', ['merman_tone3', 'merman_medium_skin_tone']),
  EmojiEntry('🧜🏾‍♀️', ['mermaid_tone4', 'mermaid_medium_dark_skin_tone']),
  EmojiEntry('🧜🏾‍♂️', ['merman_tone4', 'merman_medium_dark_skin_tone']),
  EmojiEntry('🧜🏿‍♀️', ['mermaid_tone5', 'mermaid_dark_skin_tone']),
  EmojiEntry('🧜🏿‍♂️', ['merman_tone5', 'merman_dark_skin_tone']),
  EmojiEntry('🧝‍♀️', ['woman_elf']),
  EmojiEntry('🧝‍♂️', ['man_elf']),
  EmojiEntry('🧝🏻‍♀️', ['woman_elf_tone1', 'woman_elf_light_skin_tone']),
  EmojiEntry('🧝🏻‍♂️', ['man_elf_tone1', 'man_elf_light_skin_tone']),
  EmojiEntry('🧝🏼‍♀️', ['woman_elf_tone2', 'woman_elf_medium_light_skin_tone']),
  EmojiEntry('🧝🏼‍♂️', ['man_elf_tone2', 'man_elf_medium_light_skin_tone']),
  EmojiEntry('🧝🏽‍♀️', ['woman_elf_tone3', 'woman_elf_medium_skin_tone']),
  EmojiEntry('🧝🏽‍♂️', ['man_elf_tone3', 'man_elf_medium_skin_tone']),
  EmojiEntry('🧝🏾‍♀️', ['woman_elf_tone4', 'woman_elf_medium_dark_skin_tone']),
  EmojiEntry('🧝🏾‍♂️', ['man_elf_tone4', 'man_elf_medium_dark_skin_tone']),
  EmojiEntry('🧝🏿‍♀️', ['woman_elf_tone5', 'woman_elf_dark_skin_tone']),
  EmojiEntry('🧝🏿‍♂️', ['man_elf_tone5', 'man_elf_dark_skin_tone']),
  EmojiEntry('🧞‍♀️', ['woman_genie']),
  EmojiEntry('🧞‍♂️', ['man_genie']),
  EmojiEntry('🧟‍♀️', ['woman_zombie']),
  EmojiEntry('🧟‍♂️', ['man_zombie']),
  EmojiEntry('🧖‍♀️', ['woman_in_steamy_room']),
  EmojiEntry('🧖‍♂️', ['man_in_steamy_room']),
  EmojiEntry('🧖🏻‍♀️', ['woman_in_steamy_room_tone1', 'woman_in_steamy_room_light_skin_tone']),
  EmojiEntry('🧖🏻‍♂️', ['man_in_steamy_room_tone1', 'man_in_steamy_room_light_skin_tone']),
  EmojiEntry('🧖🏼‍♀️', ['woman_in_steamy_room_tone2', 'woman_in_steamy_room_medium_light_skin_tone']),
  EmojiEntry('🧖🏼‍♂️', ['man_in_steamy_room_tone2', 'man_in_steamy_room_medium_light_skin_tone']),
  EmojiEntry('🧖🏽‍♀️', ['woman_in_steamy_room_tone3', 'woman_in_steamy_room_medium_skin_tone']),
  EmojiEntry('🧖🏽‍♂️', ['man_in_steamy_room_tone3', 'man_in_steamy_room_medium_skin_tone']),
  EmojiEntry('🧖🏾‍♀️', ['woman_in_steamy_room_tone4', 'woman_in_steamy_room_medium_dark_skin_tone']),
  EmojiEntry('🧖🏾‍♂️', ['man_in_steamy_room_tone4', 'man_in_steamy_room_medium_dark_skin_tone']),
  EmojiEntry('🧖🏿‍♀️', ['woman_in_steamy_room_tone5', 'woman_in_steamy_room_dark_skin_tone']),
  EmojiEntry('🧖🏿‍♂️', ['man_in_steamy_room_tone5', 'man_in_steamy_room_dark_skin_tone']),
  EmojiEntry('🧗‍♀️', ['woman_climbing']),
  EmojiEntry('🧗‍♂️', ['man_climbing']),
  EmojiEntry('🧗🏻‍♀️', ['woman_climbing_tone1', 'woman_climbing_light_skin_tone']),
  EmojiEntry('🧗🏻‍♂️', ['man_climbing_tone1', 'man_climbing_light_skin_tone']),
  EmojiEntry('🧗🏼‍♀️', ['woman_climbing_tone2', 'woman_climbing_medium_light_skin_tone']),
  EmojiEntry('🧗🏼‍♂️', ['man_climbing_tone2', 'man_climbing_medium_light_skin_tone']),
  EmojiEntry('🧗🏽‍♀️', ['woman_climbing_tone3', 'woman_climbing_medium_skin_tone']),
  EmojiEntry('🧗🏽‍♂️', ['man_climbing_tone3', 'man_climbing_medium_skin_tone']),
  EmojiEntry('🧗🏾‍♀️', ['woman_climbing_tone4', 'woman_climbing_medium_dark_skin_tone']),
  EmojiEntry('🧗🏾‍♂️', ['man_climbing_tone4', 'man_climbing_medium_dark_skin_tone']),
  EmojiEntry('🧗🏿‍♀️', ['woman_climbing_tone5', 'woman_climbing_dark_skin_tone']),
  EmojiEntry('🧗🏿‍♂️', ['man_climbing_tone5', 'man_climbing_dark_skin_tone']),
  EmojiEntry('🧘‍♀️', ['woman_in_lotus_position']),
  EmojiEntry('🧘‍♂️', ['man_in_lotus_position']),
  EmojiEntry('🧘🏻‍♀️', ['woman_in_lotus_position_tone1', 'woman_in_lotus_position_light_skin_tone']),
  EmojiEntry('🧘🏻‍♂️', ['man_in_lotus_position_tone1', 'man_in_lotus_position_light_skin_tone']),
  EmojiEntry('🧘🏼‍♀️', ['woman_in_lotus_position_tone2', 'woman_in_lotus_position_medium_light_skin_tone']),
  EmojiEntry('🧘🏼‍♂️', ['man_in_lotus_position_tone2', 'man_in_lotus_position_medium_light_skin_tone']),
  EmojiEntry('🧘🏽‍♀️', ['woman_in_lotus_position_tone3', 'woman_in_lotus_position_medium_skin_tone']),
  EmojiEntry('🧘🏽‍♂️', ['man_in_lotus_position_tone3', 'man_in_lotus_position_medium_skin_tone']),
  EmojiEntry('🧘🏾‍♀️', ['woman_in_lotus_position_tone4', 'woman_in_lotus_position_medium_dark_skin_tone']),
  EmojiEntry('🧘🏾‍♂️', ['man_in_lotus_position_tone4', 'man_in_lotus_position_medium_dark_skin_tone']),
  EmojiEntry('🧘🏿‍♀️', ['woman_in_lotus_position_tone5', 'woman_in_lotus_position_dark_skin_tone']),
  EmojiEntry('🧘🏿‍♂️', ['man_in_lotus_position_tone5', 'man_in_lotus_position_dark_skin_tone']),

];

class EmojiEntry {
  final String emoji;
  final List<String> keywords;
  const EmojiEntry(this.emoji, this.keywords);
}

bool isValidEmoji(String emoji) => emoji.isNotEmpty;

const _kMustAddPostfixCodes = {0x2122, 0x00A9, 0x00AE};

String _applyPostfix(String emoji) {
  if (emoji.length == 1) {
    final code = emoji.codeUnitAt(0);
    if (_kMustAddPostfixCodes.contains(code)) {
      return '$emoji️';
    }
  }
  return emoji;
}

final _letterRegex = RegExp(r'\p{L}', unicode: true);

bool _skipExactKeyword(String langCode, String word) {
  if (word.length == 1 && !_letterRegex.hasMatch(word)) return true;
  if (word == '10') return true;
  if (langCode != 'en') return false;
  if (word.length == 1 && word != '\$' && word.codeUnitAt(0) != 0x20AC) return true;
  if (word.length == 2 && !const {'us', 'uk', 'hi', 'ok'}.contains(word)) return true;
  return false;
}

class _LangPack {
  final Map<String, List<String>> keywords = {};
  final List<String> sortedKeys = [];
  int version = 0;
  int maxKeyLength = 0;

  void load(Map<String, List<String>> data, int ver) {
    keywords.clear();
    sortedKeys.clear();
    maxKeyLength = 0;
    for (final entry in data.entries) {
      final key = entry.key.toLowerCase().trim();
      if (key.isEmpty) continue;
      final emojis = entry.value.map(_applyPostfix).toList();
      keywords[key] = emojis;
      if (key.length > maxKeyLength) maxKeyLength = key.length;
    }
    sortedKeys.addAll(keywords.keys);
    sortedKeys.sort();
    version = ver;
  }
}

/// A built-in suggestion candidate: the emoji entry plus, per keyword, the
/// keyword split into words sorted by first character — the shape AyuGram's
/// `Completer` needs for interior-word matching.
class _LegacyCandidate {
  final EmojiEntry entry;
  final List<List<String>> wordLists;
  const _LegacyCandidate(this.entry, this.wordLists);
}

/// A ranked built-in match (one per emoji), carrying the keys AyuGram's
/// `Completer::prepareResult` uses to order suggestions. There is deliberately
/// NO `isExact` field: C++'s 4th `stable_partition` (the exact-match boost) is
/// dead code that never reorders — see `_legacyRankKey`.
class _LegacyResult {
  final EmojiEntry entry;
  final int wordsUsed;
  final bool firstCharGood;
  const _LegacyResult(this.entry, this.wordsUsed, this.firstCharGood);
}

/// Mirrors `Completer::NormalizeQuery` (emoji_suggestions.cpp:193): drop every
/// char that is not a letter or number, keeping '-'/'+' only when followed by a
/// number or at the end. Fed the RAW (un-lowercased) query, exactly as C++
/// `AppendLegacySuggestions(result, query)` passes the original arg, NOT the
/// lowercased `normalized` the lang packs use (emoji_keywords.cpp:639). The
/// letter test is intentionally lowercase-only (`'a'..'z'`), mirroring C++
/// `IsLetterOrNumber` (emoji_suggestions.cpp:101-103): an all-uppercase shortcode
/// (`:TM`) therefore normalizes to EMPTY and yields no built-in suggestion —
/// the empty-query early-out in `resolve()` (emoji_suggestions.cpp:225-227).
String _normalizeLegacyQuery(String q) {
  final sb = StringBuffer();
  for (int i = 0; i < q.length; i++) {
    final c = q.codeUnitAt(i);
    final isNum = c >= 0x30 && c <= 0x39;
    final isLetter = c >= 0x61 && c <= 0x7A;
    if (isLetter || isNum) {
      sb.writeCharCode(c);
    } else if (c == 0x2D || c == 0x2B) {
      final atEnd = i + 1 == q.length;
      final nextNum =
          !atEnd && q.codeUnitAt(i + 1) >= 0x30 && q.codeUnitAt(i + 1) <= 0x39;
      if (atEnd || nextNum) sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

/// Mirrors codegen's `ReplacementWords` (replaces.cpp:40-63): splits a built-in
/// keyword into words on every char that is NOT a letter or number, keeping
/// '-'/'+' inside a word only when immediately followed by a number. So
/// `blond-haired_man` → [blond, haired, man], `e-mail` → [e, mail],
/// `fleur-de-lis` → [de, fleur, lis], `non-potable_water` → [non, potable,
/// water] — letting interior-word queries (`:haired`, `:mail`, `:de`/`:lis`,
/// `:potable`) match, where the old `split('_')` kept them as one word and
/// matched nothing. Returned sorted (the C++ QMap iterates keys in order), which
/// is what the interior-word matcher (`_matchLegacyTail`/`_legacyLowerBound`)
/// relies on, and duplicate words are kept (QMap re-emits each key `count`
/// times). Built-in keywords are ASCII shortcodes, so the ASCII letter/number
/// tests are equivalent to Qt's `isLetterOrNumber()`/`isNumber()` for this data.
List<String> _splitReplacementWords(String s) {
  final words = <String>[];
  final sb = StringBuffer();
  void feed() {
    if (sb.isNotEmpty) {
      words.add(sb.toString());
      sb.clear();
    }
  }

  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final isNumber = c >= 0x30 && c <= 0x39;
    final isLetterOrNumber =
        isNumber || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
    if (isLetterOrNumber) {
      sb.writeCharCode(c);
      continue;
    } else if (c == 0x2D || c == 0x2B) {
      // '-' or '+': keep only if the next char is a number.
      final next = i + 1 < s.length ? s.codeUnitAt(i + 1) : -1;
      if (next >= 0x30 && next <= 0x39) {
        sb.writeCharCode(c);
        continue;
      }
    }
    feed();
  }
  feed();
  words.sort();
  return words;
}

/// Mirrors `Completer::matchQueryForCurrentItem` (emoji_suggestions.cpp:301):
/// returns the words-used count on a match, or -1 on no match. Single-word
/// replacements match only as a prefix-from-start; multi-word replacements allow
/// interior-word matching via [_matchLegacyTail].
int _matchLegacyWords(List<String> words, String q) {
  if (words.length < 2) {
    return _legacyStartsWith(words[0], q) ? 1 : -1;
  }
  final used = List<bool>.filled(words.length, false);
  return _matchLegacyTail(words, q, 0, used, 1);
}

/// Mirrors `Completer::matchQueryTailStartingFrom` (emoji_suggestions.cpp:333):
/// greedily assign query chunks (largest first) to distinct words whose first
/// char matches the current query char, recursing until the query is consumed.
int _matchLegacyTail(
    List<String> words, String q, int position, List<bool> used, int wordsUsed) {
  if (position >= q.length) return wordsUsed;
  final firstChar = q.codeUnitAt(position);
  final lo = _legacyLowerBound(words, firstChar);
  for (int wi = lo; wi < words.length && words[wi].codeUnitAt(0) == firstChar; wi++) {
    if (used[wi]) continue;
    used[wi] = true;
    final equal = _legacyEqualChars(q, position, words[wi]);
    for (int check = equal; check > 0; check--) {
      final r = _matchLegacyTail(words, q, position + check, used, wordsUsed + 1);
      if (r >= 0) return r;
    }
    used[wi] = false;
  }
  return -1;
}

/// First index whose word starts with a char >= [ch] (lower_bound over the
/// first-char-sorted word list, as `Completer::findWordsStartingWith` needs).
int _legacyLowerBound(List<String> words, int ch) {
  int lo = 0, hi = words.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (words[mid].codeUnitAt(0) < ch) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Mirrors `Completer::startsWithQuery` (emoji_suggestions.cpp:309).
bool _legacyStartsWith(String word, String q) {
  if (word.length < q.length) return false;
  for (int i = 0; i < q.length; i++) {
    if (word.codeUnitAt(i) != q.codeUnitAt(i)) return false;
  }
  return true;
}

/// Mirrors `Completer::findEqualCharsCount` (emoji_suggestions.cpp:358): chars
/// of the query (from [position]) that match the word's prefix, capped. The
/// first char is assumed equal (the word was found by it), so it starts at 1.
int _legacyEqualChars(String q, int position, String word) {
  final charsLeft = q.length - position;
  final wordSize = word.length;
  final possible = charsLeft < wordSize ? charsLeft : wordSize;
  for (int equalTill = 1; equalTill < possible; equalTill++) {
    if (word.codeUnitAt(equalTill) != q.codeUnitAt(position + equalTill)) {
      return equalTill;
    }
  }
  return possible;
}

/// Lower = higher priority, mirroring the stacked `stable_partition`s in
/// `Completer::prepareResult` (emoji_suggestions.cpp:373-393). C++ applies four
/// partitions; the LAST applied is the most dominant sort key. The 4th (most
/// dominant) partition would boost `isExactMatch`, but it is DEAD CODE: it is
/// size-gated `replacement.size() == _initialQuery.size() + 1`
/// (emoji_suggestions.cpp:322), comparing the colon-wrapped baked replacement
/// (`":key:"`, the `^:[\+\-a-z0-9_]+:$` codegen form, length keyword+2) against
/// the leading-colon-stripped query (`"key"`, length keyword, stripped at
/// emoji_suggestions_widget.cpp:326). `keyword+2 == keyword+1` is never true, so
/// that partition never reorders and C++ keeps declaration order for same-rank
/// results. We therefore do NOT boost exact matches — an exact built-in keyword
/// (`:key:`→🔑) must not float ahead of an equal-rank prefix match
/// (`keyboard`→⌨️). Only the three real partitions apply: words-used < 3, then
/// < 2, then shortcode-first-char == query-first-char (least dominant, applied
/// first in C++).
int _legacyRankKey(_LegacyResult r) {
  final w3 = r.wordsUsed < 3 ? 0 : 1;
  final w2 = r.wordsUsed < 2 ? 0 : 1;
  final fc = r.firstCharGood ? 0 : 1;
  return (w3 << 2) | (w2 << 1) | fc;
}

/// Manages emoji keyword data from server language packs with local fallback.
class EmojiKeywords {
  EmojiKeywords._();
  static final instance = EmojiKeywords._();

  final Map<String, _LangPack> _langPacks = {};

  final List<String> _recentEmojis = [];
  static const _maxRecent = 50;

  final Map<String, String> _variantPrefs = {};

  Timer? _refreshTimer;
  Timer? _saveDebounce;
  void Function()? _onSave;
  String? _cacheDir;

  final _refreshedController = StreamController<void>.broadcast();
  Stream<void> get refreshed => _refreshedController.stream;

  static final _badSuggestionChar = RegExp(r'[^a-zA-Z0-9_\-+]');
  static final _skinToneRe = RegExp(r'[\u{1F3FB}-\u{1F3FF}]', unicode: true);
  static String _stripSkinTone(String emoji) =>
      emoji.replaceAll(_skinToneRe, '');

  late final int _legacyMaxKeyLength = _computeLegacyMaxKeyLength();

  static int _computeLegacyMaxKeyLength() {
    int max = 0;
    for (final e in kEmojiSuggestions) {
      for (final kw in e.keywords) {
        if (kw.length > max) max = kw.length;
      }
    }
    return max;
  }

  /// Built-in suggestions pre-split into sorted words per keyword — the shape
  /// AyuGram's `Completer` needs for interior-word matching (built once).
  late final List<_LegacyCandidate> _legacyCandidates = _buildLegacyCandidates();

  static List<_LegacyCandidate> _buildLegacyCandidates() {
    final out = <_LegacyCandidate>[];
    for (final e in kEmojiSuggestions) {
      final lists = <List<String>>[];
      for (final kw in e.keywords) {
        lists.add(_splitReplacementWords(kw));
      }
      out.add(_LegacyCandidate(e, lists));
    }
    return out;
  }

  void init({String? cacheDir, void Function()? saveCallback}) {
    if (cacheDir != null) {
      _cacheDir = cacheDir;
      loadCacheFromDisk();
    }
    if (saveCallback != null) {
      _onSave = saveCallback;
    }
  }

  void setSaveCallback(void Function() callback) {
    _onSave = callback;
  }

  void setCacheDir(String dir) {
    _cacheDir = dir;
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _onSave?.call();
    });
  }

  int maxQueryLength() {
    int max = _legacyMaxKeyLength;
    for (final pack in _langPacks.values) {
      if (pack.maxKeyLength > max) max = pack.maxKeyLength;
    }
    return max;
  }

  void loadServerKeywords({
    required Map<String, List<String>> keywords,
    required int version,
    required String langCode,
  }) {
    final pack = _langPacks.putIfAbsent(langCode, _LangPack.new);
    final isNew = pack.version == 0;
    pack.load(keywords, version);
    _refreshedController.add(null);
    if (_cacheDir != null) {
      _writeCacheToDiskAsync(langCode, keywords, version);
    }
    if (isNew) {
      _scheduleSave();
    }
  }

  void loadServerKeywordsDiff({
    required Map<String, List<String>> keywords,
    required Map<String, List<String>> deleted,
    required int version,
    required String langCode,
  }) {
    final pack = _langPacks.putIfAbsent(langCode, _LangPack.new);
    for (final entry in keywords.entries) {
      final key = entry.key.toLowerCase().trim();
      if (key.isEmpty) continue;
      if (entry.value.isEmpty) continue;
      final existing = pack.keywords[key];
      if (existing != null) {
        final existingSet = existing.toSet();
        for (final e in entry.value) {
          final emoji = _applyPostfix(e);
          if (!existingSet.contains(emoji)) {
            existing.add(emoji);
          }
        }
      } else {
        pack.keywords[key] = entry.value.map(_applyPostfix).toList();
      }
    }
    for (final entry in deleted.entries) {
      final key = entry.key.toLowerCase().trim();
      if (key.isEmpty) continue;
      final existing = pack.keywords[key];
      if (existing == null) continue;
      // Stored emojis are postfixed via _applyPostfix (™→™️ etc.), but the
      // server sends the raw deleted text, so postfix it too before matching.
      // Mirrors AyuGram removing by LangPackEmoji::text once both sides share
      // the same postfix rule (emoji_keywords.cpp:284-288).
      final removeSet = entry.value.map(_applyPostfix).toSet();
      existing.removeWhere(removeSet.contains);
      if (existing.isEmpty) {
        pack.keywords.remove(key);
      }
    }
    pack.sortedKeys.clear();
    pack.sortedKeys.addAll(pack.keywords.keys);
    pack.sortedKeys.sort();
    pack.maxKeyLength = pack.sortedKeys.fold(0, (m, k) => k.length > m ? k.length : m);
    pack.version = version;
    _refreshedController.add(null);
    if (_cacheDir != null) {
      _writeCacheToDiskAsync(langCode, pack.keywords, version);
    }
  }

  Future<void> _writeCacheToDiskAsync(String langCode, Map<String, List<String>> kw, int version) async {
    final cacheDir = _cacheDir;
    if (cacheDir == null) return;
    try {
      await Isolate.run(() {
        final dir = Directory('$cacheDir/keywords');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        File('${dir.path}/$langCode.json')
            .writeAsStringSync(json.encode({'v': version, 'kw': kw}));
      });
    } catch (e) {
      Debug.log('emoji_data', 'await Isolate.run((): $e');
    }
  }

  Future<void> loadCacheFromDisk() async {
    final cacheDir = _cacheDir;
    if (cacheDir == null) return;
    try {
      final parsed = await Isolate.run(() {
        final dir = Directory('$cacheDir/keywords');
        if (!dir.existsSync()) return <String, Map<String, dynamic>>{};
        final result = <String, Map<String, dynamic>>{};
        for (final f in dir.listSync()) {
          if (f is! File || !f.path.endsWith('.json')) continue;
          final langCode = f.uri.pathSegments.last.replaceAll('.json', '');
          result[langCode] =
              json.decode(f.readAsStringSync()) as Map<String, dynamic>;
        }
        return result;
      });
      for (final entry in parsed.entries) {
        final version = entry.value['v'] as int? ?? 0;
        final kw = (entry.value['kw'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as List).cast<String>()),
        );
        final pack = _langPacks.putIfAbsent(entry.key, _LangPack.new);
        pack.load(kw, version);
      }
    } catch (e) {
      Debug.log('emoji_data', 'final parsed = await Isolate.run((): $e');
    }
  }

  bool get hasServerData => _langPacks.isNotEmpty;
  int get serverVersion => _langPacks.values.fold(0, (m, p) => p.version > m ? p.version : m);
  String get serverLangCode => _langPacks.keys.firstOrNull ?? '';
  int versionForLang(String langCode) => _langPacks[langCode]?.version ?? 0;
  bool hasLangData(String langCode) => _langPacks.containsKey(langCode);

  void startAutoRefresh(Future<void> Function() refreshCallback) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) => refreshCallback());
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void recordRecent(String emoji) {
    _recentEmojis.remove(emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > _maxRecent) {
      _recentEmojis.removeLast();
    }
    _scheduleSave();
  }

  /// The set of every built-in emoji (default/yellow form), used to detect
  /// emoji inside sent message text. Built once.
  late final Set<String> _knownEmojiSet = {
    for (final e in kEmojiSuggestions) e.emoji,
  };

  /// Records every standard emoji found in [text] as recent. AyuGram's
  /// `recentEmoji()` is the single global list `PrioritizeRecent` reads, and it
  /// is updated whenever an emoji passes through the text engine — including
  /// message text — via `UiIntegration::defaultEmojiVariant`
  /// (ui_integration.cpp:471). Wiring this into the send path keeps inline
  /// suggestion ordering in sync with what the user actually sends, instead of
  /// only with accepted autocomplete picks. Skin-tone variants are recorded as
  /// used (their base is a known emoji); `_prioritizeRecent` strips the tone
  /// when matching against suggestions.
  void recordRecentFromText(String text) {
    if (text.isEmpty) return;
    for (final cluster in text.characters) {
      if (_knownEmojiSet.contains(cluster)) {
        recordRecent(cluster);
      } else {
        final base = _stripSkinTone(cluster);
        if (base != cluster && _knownEmojiSet.contains(base)) {
          recordRecent(cluster);
        }
      }
    }
  }

  List<String> get recentEmojis => List.unmodifiable(_recentEmojis);

  /// Resolves an emoji to the user's chosen skin-tone variant for inline
  /// suggestions. Wired by the emoji panel — the single source of truth for
  /// skin-tone preferences — mirroring AyuGram's `EmojiKeywords::ApplyVariants`
  /// delegating to `Settings::lookupEmojiVariant`. When unset, suggestions keep
  /// the default (yellow) tone.
  String Function(String emoji)? skinToneResolver;

  void setVariant(String baseEmoji, String variant) {
    _variantPrefs[baseEmoji] = variant;
    _scheduleSave();
  }

  String applyVariant(String emoji) {
    final resolver = skinToneResolver;
    if (resolver != null) {
      final resolved = resolver(emoji);
      if (resolved.isNotEmpty) return resolved;
    }
    return _variantPrefs[emoji] ?? emoji;
  }

  void loadState(Map<String, dynamic> data) {
    final recent = data['recent'] as List<dynamic>?;
    if (recent != null) {
      _recentEmojis.clear();
      _recentEmojis.addAll(recent.cast<String>().take(_maxRecent));
    }
    final variants = data['variants'] as Map<String, dynamic>?;
    if (variants != null) {
      _variantPrefs.clear();
      variants.forEach((k, v) => _variantPrefs[k] = v as String);
    }
  }

  Map<String, dynamic> saveState() => {
    'recent': _recentEmojis,
    'variants': _variantPrefs,
  };

  List<EmojiEntry> search(String query, {int limit = 30, bool exact = false}) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();

    final maxLen = maxQueryLength();
    if (maxLen > 0 && q.length > maxLen) return const [];

    // Mirrors AyuGram `EmojiKeywords::query` (emoji_keywords.cpp:608-642): each
    // language pack's full result is appended in turn (server data), then the
    // built-in fallback is appended STRICTLY AFTER all packs
    // (`AppendLegacySuggestions`, :639). There is NO global exact-vs-prefix
    // bucketing across sources — a built-in/legacy EXACT match must NOT float
    // ahead of a server-pack PREFIX match. Each pack's own query already orders
    // exact-key emoji before prefix-key emoji via lexicographic key iteration.
    //
    // CASE HANDLING (matches C++ exactly): lang packs are queried on the
    // lowercased `q` (C++ `normalized = NormalizeQuery(query) = query.toLower()`,
    // emoji_keywords.cpp:611+168-170), but the legacy/built-in fallback is
    // queried on the RAW (un-lowercased) `query` (C++ `AppendLegacySuggestions(
    // result, query)`, :639 — the original arg, not `normalized`). Because the
    // legacy normalize drops every non-lowercase-letter char, an all-uppercase
    // shortcode (`:TM`) yields NO built-in match — only a server pack keyed on
    // `tm` can answer it.
    final result = <EmojiEntry>[];
    final seen = <String>{};

    for (final pack in _langPacks.entries) {
      _searchLangPack(pack.key, pack.value, q, exact, seen, result);
    }

    if (!exact) {
      _searchLegacyData(query, seen, result);
    }

    final prioritized = _prioritizeRecent(result);

    final mapped = prioritized.map((e) {
      final variant = applyVariant(e.emoji);
      return variant == e.emoji ? e : EmojiEntry(variant, e.keywords);
    }).toList();

    return mapped.length > limit ? mapped.sublist(0, limit) : mapped;
  }

  void _searchLangPack(
    String langCode,
    _LangPack pack,
    String q,
    bool exact,
    Set<String> seen,
    List<EmojiEntry> result,
  ) {
    if (pack.keywords.isEmpty) return;
    if (q.length > pack.maxKeyLength) return;
    if (exact && _skipExactKeyword(langCode, q)) return;

    // Mirrors `EmojiKeywords::LangPack::query` (emoji_keywords.cpp:473-496):
    // iterate keys from `lower_bound(q)` while they still match, appending each
    // key's emoji in lexicographic order. The exact key `q` sorts first (it is
    // the shortest key with that prefix), so exact-key emoji naturally precede
    // prefix-key emoji within the pack — no separate exact bucket needed. Exact
    // mode keeps only the exact key (`take_while(key == q)`).
    final keys = pack.sortedKeys;
    int lo = 0, hi = keys.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (keys[mid].compareTo(q) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (int i = lo; i < keys.length; i++) {
      final keyword = keys[i];
      if (exact) {
        if (keyword != q) break;
      } else if (!keyword.startsWith(q)) {
        break;
      }
      final emojis = pack.keywords[keyword]!;
      for (final emoji in emojis) {
        if (seen.add(emoji)) result.add(EmojiEntry(emoji, [keyword]));
      }
    }
  }

  /// Built-in/legacy completer fallback. [rawQuery] is the RAW (un-lowercased)
  /// query, mirroring C++ `AppendLegacySuggestions(result, query)`
  /// (emoji_keywords.cpp:639) — the original arg, NOT the lowercased form the
  /// lang packs use. `_normalizeLegacyQuery` keeps only lowercase letters/digits
  /// (C++ `IsLetterOrNumber`, emoji_suggestions.cpp:101-103), so an all-uppercase
  /// shortcode normalizes to empty and produces no suggestion here.
  void _searchLegacyData(
    String rawQuery,
    Set<String> seen,
    List<EmojiEntry> result,
  ) {
    if (_badSuggestionChar.hasMatch(rawQuery)) return;
    final normalized = _normalizeLegacyQuery(rawQuery);
    if (normalized.isEmpty) return;
    final querySize = normalized.length;
    final firstChar = normalized.codeUnitAt(0);

    // Collect the best-ranked match per emoji, allowing interior-word matches
    // (AyuGram Completer — e.g. "police" matches ":oncoming_police_car:"), then
    // order them by Completer::prepareResult priority.
    final results = <_LegacyResult>[];
    for (final cand in _legacyCandidates) {
      final emoji = cand.entry.emoji;
      if (seen.contains(emoji)) continue;
      _LegacyResult? best;
      int bestKey = 0;
      for (int ki = 0; ki < cand.wordLists.length; ki++) {
        final words = cand.wordLists[ki];
        if (words.isEmpty) continue;
        final matched = _matchLegacyWords(words, normalized);
        if (matched < 0) continue;
        // Single-character fast path: `Completer::processInitialList`
        // (emoji_suggestions.cpp:267-276) short-circuits when `_querySize == 1`
        // and adds EVERY first-char-indexed candidate with `wordsUsed = 1`, with
        // no matching pass. So a multi-word candidate matched on an interior word
        // is NOT demoted to `wordsUsed = 2` (which `_legacyRankKey` would push
        // below single-word matches). Same result set, but the AyuGram order.
        final wordsUsed = querySize == 1 ? 1 : matched;
        final rawKw = cand.entry.keywords[ki];
        final candidate = _LegacyResult(
          cand.entry,
          wordsUsed,
          rawKw.isNotEmpty && rawKw.codeUnitAt(0) == firstChar,
        );
        final key = _legacyRankKey(candidate);
        if (best == null || key < bestKey) {
          best = candidate;
          bestKey = key;
        }
      }
      if (best != null) {
        seen.add(emoji);
        results.add(best);
      }
    }
    if (results.isEmpty) return;

    // Stable-sort by rank key; original (declaration) order breaks ties, exactly
    // as the stacked stable_partitions in prepareResult preserve relative order.
    // The whole legacy block is appended AFTER all language-pack results
    // (AppendLegacySuggestions). C++'s 4th partition would boost exact matches
    // but is dead code (see `_legacyRankKey`), so an exact built-in keyword does
    // NOT float ahead of an equal-rank prefix match — declaration order is kept.
    final order = List<int>.generate(results.length, (i) => i);
    order.sort((a, b) {
      final ka = _legacyRankKey(results[a]);
      final kb = _legacyRankKey(results[b]);
      if (ka != kb) return ka - kb;
      return a - b;
    });
    for (final i in order) {
      result.add(results[i].entry);
    }
  }

  List<EmojiEntry> _prioritizeRecent(List<EmojiEntry> list) {
    if (_recentEmojis.isEmpty || list.isEmpty) return list;
    final result = List<EmojiEntry>.from(list);
    // Mirrors AyuGram PrioritizeRecent (emoji_keywords.cpp:650-672): for each
    // recent, search the whole list from the start and rotate the match to the
    // frontier ONLY when it sits strictly past it (`it > lastRecent`). A match
    // already at (or before) the frontier does not advance it — so equal-front
    // recents get leapfrogged, e.g. list [A,B] + recent [A,B] → [B,A].
    var lastRecent = 0;
    for (final recent in _recentEmojis) {
      final base = _stripSkinTone(recent);
      final idx = result.indexWhere((e) => _stripSkinTone(e.emoji) == base);
      if (idx > lastRecent) {
        final item = result.removeAt(idx);
        result.insert(lastRecent, item);
        lastRecent++;
      }
    }
    return result;
  }
}

List<EmojiEntry> searchEmoji(String query, {int limit = 30, bool exact = false}) {
  return EmojiKeywords.instance.search(query, limit: limit, exact: exact);
}
