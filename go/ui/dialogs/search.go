package dialogs

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const searchWordSplitSet = "@-+()[]{}<>,.:!_;\"'"

var translitWordOverrides = map[string]string{
	"Александр": "Alexander",
	"александр": "alexander",
	"Филипп":    "Philip",
	"филипп":    "philip",
	"Пётр":      "Petr",
	"пётр":      "petr",
	"Гай":       "Gai",
	"гай":       "gai",
	"Ильин":     "Ilyin",
	"ильин":     "ilyin",
}

var translitDoubleLetters = map[string]string{
	"Ый": "Y",
	"ия": "ia",
	"ий": "y",
	"кс": "x",
	"ый": "y",
	"ье": "ye",
}

var translitSingleLetters = map[rune]string{
	'А': "A", 'Б': "B", 'В': "V", 'Г': "G", 'Ґ': "G", 'Д': "D",
	'Е': "E", 'Є': "Ye", 'Ё': "Yo", 'Ж': "Zh", 'З': "Z", 'И': "I",
	'Ї': "Yi", 'І': "I", 'Й': "J", 'К': "K", 'Л': "L", 'М': "M",
	'Н': "N", 'О': "O", 'П': "P", 'Р': "R", 'С': "S", 'Т': "T",
	'У': "U", 'Ў': "W", 'Ф': "F", 'Х': "Kh", 'Ц': "Ts", 'Ч': "Ch",
	'Ш': "Sh", 'Щ': "Sch", 'Ъ': "", 'Ы': "Y", 'Ь': "", 'Э': "E",
	'Ю': "Yu", 'Я': "Ya",
	'а': "a", 'б': "b", 'в': "v", 'г': "g", 'ґ': "g", 'д': "d",
	'е': "e", 'є': "ye", 'ё': "yo", 'ж': "zh", 'з': "z", 'и': "i",
	'й': "y", 'ї': "yi", 'і': "i", 'к': "k", 'л': "l", 'м': "m",
	'н': "n", 'о': "o", 'п': "p", 'р': "r", 'с': "s", 'т': "t",
	'у': "u", 'ў': "w", 'ф': "f", 'х': "kh", 'ц': "ts", 'ч': "ch",
	'ш': "sh", 'щ': "sch", 'ъ': "", 'ы': "y", 'ь': "", 'э': "e",
	'ю': "yu", 'я': "ya",
}

func translitRusEng(s string) string {
	if v, ok := translitWordOverrides[s]; ok {
		return v
	}
	var b strings.Builder
	b.Grow(len(s) * 2)
	rs := []rune(s)
	for i := 0; i < len(rs); {
		if i+1 < len(rs) {
			if v, ok := translitDoubleLetters[string(rs[i:i+2])]; ok {
				b.WriteString(v)
				i += 2
				continue
			}
		}
		if v, ok := translitSingleLetters[rs[i]]; ok {
			b.WriteString(v)
		} else {
			b.WriteRune(rs[i])
		}
		i++
	}
	return b.String()
}

const engKeyboardRow = "qwertyuiop[]asdfghjkl;'zxcvbnm,."
const rusKeyboardRow = "йцукенгшщзхъфывапролджэячсмитьбю"
const ukrKeyboardRow = "йцукенгшщзхїфівапролджєячсмитьбю"

func buildKeyboardSwitch(a, b string) map[rune]rune {
	ar := []rune(a)
	br := []rune(b)
	m := make(map[rune]rune, len(ar)*4)
	for i := range ar {
		au, bu := unicode.ToUpper(ar[i]), unicode.ToUpper(br[i])
		m[ar[i]] = br[i]
		m[br[i]] = ar[i]
		m[au] = bu
		m[bu] = au
	}
	return m
}

var rusKeyboardSwitch = buildKeyboardSwitch(engKeyboardRow, rusKeyboardRow)
var ukrKeyboardSwitch = buildKeyboardSwitch(engKeyboardRow, ukrKeyboardRow)

func switchKeyboardLayout(s string, m map[rune]rune) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if v, ok := m[r]; ok {
			b.WriteRune(v)
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func rusKeyboardLayoutSwitch(s string) string {
	rus := switchKeyboardLayout(s, rusKeyboardSwitch)
	ukr := switchKeyboardLayout(s, ukrKeyboardSwitch)
	if rus == ukr {
		return rus
	}
	return rus + " " + ukr
}

func hasRussianLetters(s string) bool {
	for _, r := range s {
		if (r >= 'а' && r <= 'я') || (r >= 'А' && r <= 'Я') || r == 'ё' || r == 'Ё' {
			return true
		}
	}
	return false
}

func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

var removeOneAccent = map[rune]rune{
	192:   'a',
	193:   'a',
	194:   'a',
	195:   'a',
	196:   'a',
	197:   'a',
	199:   'c',
	200:   'e',
	201:   'e',
	202:   'e',
	203:   'e',
	204:   'i',
	205:   'i',
	206:   'i',
	207:   'i',
	209:   'n',
	210:   'o',
	211:   'o',
	212:   'o',
	213:   'o',
	214:   'o',
	216:   'o',
	217:   'u',
	218:   'u',
	219:   'u',
	220:   'u',
	221:   'y',
	222:   't',
	223:   's',
	224:   'a',
	225:   'a',
	226:   'a',
	227:   'a',
	228:   'a',
	229:   'a',
	231:   'c',
	232:   'e',
	233:   'e',
	234:   'e',
	235:   'e',
	236:   'i',
	237:   'i',
	238:   'i',
	239:   'i',
	240:   'd',
	241:   'n',
	242:   'o',
	243:   'o',
	244:   'o',
	245:   'o',
	246:   'o',
	248:   'o',
	249:   'u',
	250:   'u',
	251:   'u',
	252:   'u',
	253:   'y',
	254:   't',
	255:   'y',
	256:   'a',
	257:   'a',
	258:   'a',
	259:   'a',
	260:   'a',
	261:   'a',
	262:   'c',
	263:   'c',
	264:   'c',
	265:   'c',
	266:   'c',
	267:   'c',
	268:   'c',
	269:   'c',
	270:   'd',
	271:   'd',
	272:   'd',
	273:   'd',
	274:   'e',
	275:   'e',
	276:   'e',
	277:   'e',
	278:   'e',
	279:   'e',
	280:   'e',
	281:   'e',
	282:   'e',
	283:   'e',
	284:   'g',
	285:   'g',
	286:   'g',
	287:   'g',
	288:   'g',
	289:   'g',
	290:   'g',
	291:   'g',
	292:   'h',
	293:   'h',
	294:   'h',
	295:   'h',
	296:   'i',
	297:   'i',
	298:   'i',
	299:   'i',
	300:   'i',
	301:   'i',
	302:   'i',
	303:   'i',
	304:   'i',
	305:   'i',
	308:   'j',
	309:   'j',
	310:   'k',
	311:   'k',
	313:   'a',
	314:   'l',
	315:   'l',
	316:   'l',
	317:   'l',
	318:   'l',
	319:   'l',
	320:   'l',
	321:   'l',
	322:   'l',
	323:   'n',
	324:   'n',
	325:   'n',
	326:   'n',
	327:   'n',
	328:   'n',
	332:   'o',
	333:   'o',
	334:   'o',
	335:   'o',
	336:   'o',
	337:   'o',
	340:   'r',
	341:   'r',
	342:   'r',
	343:   'r',
	344:   'r',
	345:   'r',
	346:   's',
	347:   's',
	348:   's',
	349:   's',
	350:   's',
	351:   's',
	352:   's',
	353:   's',
	354:   't',
	355:   't',
	356:   't',
	357:   't',
	358:   't',
	359:   't',
	360:   'u',
	361:   'u',
	362:   'u',
	363:   'u',
	364:   'u',
	365:   'u',
	366:   'u',
	367:   'u',
	368:   'u',
	369:   'u',
	370:   'u',
	371:   'u',
	372:   'w',
	373:   'w',
	374:   'y',
	375:   'y',
	376:   'y',
	377:   'z',
	378:   'z',
	379:   'z',
	380:   'z',
	381:   'z',
	382:   'z',
	384:   'b',
	385:   'b',
	386:   'b',
	387:   'b',
	391:   'c',
	392:   'c',
	393:   'd',
	394:   'd',
	395:   'd',
	396:   'd',
	398:   'e',
	399:   'e',
	401:   'f',
	402:   'f',
	403:   'g',
	407:   'i',
	408:   'k',
	409:   'k',
	410:   'l',
	413:   'n',
	414:   'n',
	415:   'o',
	416:   'o',
	417:   'o',
	420:   'p',
	421:   'p',
	427:   't',
	428:   't',
	429:   't',
	430:   't',
	431:   'u',
	432:   'u',
	434:   'v',
	435:   'y',
	436:   'y',
	437:   'z',
	438:   'z',
	442:   'z',
	461:   'a',
	462:   'a',
	463:   'i',
	464:   'i',
	465:   'o',
	466:   'o',
	467:   'u',
	468:   'u',
	469:   'u',
	470:   'u',
	471:   'u',
	472:   'u',
	473:   'u',
	474:   'u',
	475:   'u',
	476:   'u',
	477:   'e',
	478:   'a',
	479:   'a',
	480:   'a',
	481:   'a',
	482:   'a',
	483:   'a',
	484:   'g',
	485:   'g',
	486:   'g',
	487:   'g',
	488:   'k',
	489:   'k',
	490:   'o',
	491:   'o',
	492:   'o',
	493:   'o',
	494:   'z',
	495:   'z',
	496:   'j',
	500:   'g',
	501:   'g',
	504:   'n',
	505:   'n',
	506:   'a',
	507:   'a',
	508:   'a',
	509:   'a',
	510:   'o',
	511:   'o',
	512:   'a',
	513:   'a',
	514:   'a',
	515:   'a',
	516:   'e',
	517:   'e',
	518:   'e',
	519:   'e',
	520:   'i',
	521:   'i',
	522:   'i',
	523:   'i',
	524:   'o',
	525:   'o',
	526:   'o',
	527:   'o',
	528:   'r',
	529:   'r',
	530:   'r',
	531:   'r',
	532:   'u',
	533:   'u',
	534:   'u',
	535:   'u',
	536:   's',
	537:   's',
	538:   't',
	539:   't',
	542:   'h',
	543:   'h',
	544:   'n',
	545:   'd',
	548:   'z',
	549:   'z',
	550:   'a',
	551:   'a',
	552:   'e',
	553:   'e',
	554:   'o',
	555:   'o',
	556:   'o',
	557:   'o',
	558:   'o',
	559:   'o',
	560:   'o',
	561:   'o',
	562:   'y',
	563:   'y',
	564:   'l',
	565:   'n',
	566:   't',
	567:   'j',
	570:   'a',
	571:   'c',
	572:   'c',
	573:   'l',
	574:   't',
	579:   'b',
	580:   'u',
	582:   'e',
	583:   'e',
	584:   'j',
	585:   'j',
	586:   'q',
	587:   'q',
	588:   'r',
	589:   'r',
	590:   'y',
	591:   'y',
	595:   'b',
	597:   'c',
	598:   'd',
	599:   'd',
	602:   'e',
	605:   'e',
	607:   'j',
	608:   'g',
	616:   'i',
	619:   'l',
	620:   'l',
	621:   'l',
	625:   'm',
	626:   'n',
	627:   'n',
	629:   'o',
	636:   'r',
	637:   'r',
	638:   'r',
	642:   's',
	644:   'j',
	648:   't',
	649:   'u',
	651:   'v',
	655:   'y',
	656:   'z',
	657:   'z',
	669:   'j',
	672:   'q',
	771:   'p',
	776:   't',
	778:   'y',
	780:   'j',
	803:   'l',
	809:   's',
	817:   'h',
	1105:  'е',
	7532:  'b',
	7533:  'd',
	7534:  'f',
	7538:  'r',
	7539:  'r',
	7541:  't',
	7680:  'a',
	7681:  'a',
	7682:  'b',
	7683:  'b',
	7684:  'b',
	7685:  'b',
	7686:  'b',
	7687:  'b',
	7688:  'c',
	7689:  'c',
	7690:  'd',
	7691:  'd',
	7692:  'd',
	7693:  'd',
	7694:  'd',
	7695:  'd',
	7696:  'd',
	7697:  'd',
	7698:  'd',
	7699:  'd',
	7700:  'e',
	7701:  'e',
	7702:  'e',
	7703:  'e',
	7704:  'e',
	7705:  'e',
	7706:  'e',
	7707:  'e',
	7708:  'e',
	7709:  'e',
	7710:  'f',
	7711:  'f',
	7712:  'g',
	7713:  'g',
	7714:  'h',
	7715:  'h',
	7716:  'h',
	7717:  'h',
	7718:  'h',
	7719:  'h',
	7720:  'h',
	7721:  'h',
	7722:  'h',
	7723:  'h',
	7724:  'i',
	7725:  'i',
	7726:  'i',
	7727:  'i',
	7728:  'k',
	7729:  'k',
	7730:  'k',
	7731:  'k',
	7732:  'k',
	7733:  'k',
	7734:  'l',
	7735:  'l',
	7736:  'l',
	7737:  'l',
	7738:  'l',
	7739:  'l',
	7740:  'l',
	7741:  'l',
	7742:  'm',
	7743:  'm',
	7744:  'm',
	7745:  'm',
	7746:  'm',
	7747:  'm',
	7748:  'n',
	7749:  'n',
	7750:  'n',
	7751:  'n',
	7752:  'n',
	7753:  'n',
	7754:  'n',
	7755:  'n',
	7756:  'o',
	7757:  'o',
	7758:  'o',
	7759:  'o',
	7760:  'o',
	7761:  'o',
	7762:  'o',
	7763:  'o',
	7764:  'p',
	7765:  'p',
	7766:  'p',
	7767:  'p',
	7768:  'r',
	7769:  'r',
	7770:  'r',
	7771:  'r',
	7772:  'r',
	7773:  'r',
	7774:  'r',
	7775:  'r',
	7776:  's',
	7777:  's',
	7778:  's',
	7779:  's',
	7780:  's',
	7781:  's',
	7782:  's',
	7783:  's',
	7784:  's',
	7785:  's',
	7786:  't',
	7787:  't',
	7788:  't',
	7789:  't',
	7790:  't',
	7791:  't',
	7792:  't',
	7793:  't',
	7794:  'u',
	7795:  'u',
	7796:  'u',
	7797:  'u',
	7798:  'u',
	7799:  'u',
	7800:  'u',
	7801:  'u',
	7802:  'u',
	7803:  'u',
	7804:  'v',
	7805:  'v',
	7806:  'v',
	7807:  'v',
	7808:  'w',
	7809:  'w',
	7810:  'w',
	7811:  'w',
	7812:  'w',
	7813:  'w',
	7814:  'w',
	7815:  'w',
	7816:  'w',
	7817:  'w',
	7818:  'x',
	7819:  'x',
	7820:  'x',
	7821:  'x',
	7822:  'y',
	7823:  'y',
	7824:  'z',
	7825:  'z',
	7826:  'z',
	7827:  'z',
	7828:  'z',
	7829:  'z',
	7830:  'h',
	7831:  't',
	7832:  'w',
	7833:  'y',
	7834:  'a',
	7835:  's',
	7840:  'a',
	7841:  'a',
	7842:  'a',
	7843:  'a',
	7844:  'a',
	7845:  'a',
	7846:  'a',
	7847:  'a',
	7848:  'a',
	7849:  'a',
	7850:  'a',
	7851:  'a',
	7852:  'a',
	7853:  'a',
	7854:  'a',
	7855:  'a',
	7856:  'a',
	7857:  'a',
	7858:  'a',
	7859:  'a',
	7860:  'a',
	7861:  'a',
	7862:  'a',
	7863:  'a',
	7864:  'e',
	7865:  'e',
	7866:  'e',
	7867:  'e',
	7868:  'e',
	7869:  'e',
	7870:  'e',
	7871:  'e',
	7872:  'e',
	7873:  'e',
	7874:  'e',
	7875:  'e',
	7876:  'e',
	7877:  'e',
	7878:  'e',
	7879:  'e',
	7880:  'i',
	7881:  'i',
	7882:  'i',
	7883:  'i',
	7884:  'o',
	7885:  'o',
	7886:  'o',
	7887:  'o',
	7888:  'o',
	7889:  'o',
	7890:  'o',
	7891:  'o',
	7892:  'o',
	7893:  'o',
	7894:  'o',
	7895:  'o',
	7896:  'o',
	7897:  'o',
	7898:  'o',
	7899:  'o',
	7900:  'o',
	7901:  'o',
	7902:  'o',
	7903:  'o',
	7904:  'o',
	7905:  'o',
	7906:  'o',
	7907:  'o',
	7908:  'u',
	7909:  'u',
	7910:  'u',
	7911:  'u',
	7912:  'u',
	7913:  'u',
	7914:  'u',
	7915:  'u',
	7916:  'u',
	7917:  'u',
	7918:  'u',
	7919:  'u',
	7920:  'u',
	7921:  'u',
	7922:  'y',
	7923:  'y',
	7924:  'y',
	7925:  'y',
	7926:  'y',
	7927:  'y',
	7928:  'y',
	7929:  'y',
	11360: 'l',
	11361: 'l',
	11362: 'l',
	11363: 'p',
	11364: 'r',
	11365: 'a',
	11366: 't',
	11367: 'h',
	11368: 'h',
	11369: 'k',
	11370: 'k',
	11371: 'z',
	11372: 'z',
	65296: '0',
	65297: '1',
	65298: '2',
	65299: '3',
	65300: '4',
	65301: '5',
	65302: '6',
	65303: '7',
	65304: '8',
	65305: '9',
	65313: 'A',
	65314: 'B',
	65315: 'C',
	65316: 'D',
	65317: 'E',
	65318: 'F',
	65319: 'G',
	65320: 'H',
	65321: 'I',
	65322: 'J',
	65323: 'K',
	65324: 'L',
	65325: 'M',
	65326: 'N',
	65327: 'O',
	65328: 'P',
	65329: 'Q',
	65330: 'R',
	65331: 'S',
	65332: 'T',
	65333: 'U',
	65334: 'V',
	65335: 'W',
	65336: 'X',
	65337: 'Y',
	65338: 'Z',
	65345: 'a',
	65346: 'b',
	65347: 'c',
	65348: 'd',
	65349: 'e',
	65350: 'f',
	65351: 'g',
	65352: 'h',
	65353: 'i',
	65354: 'j',
	65355: 'k',
	65356: 'l',
	65357: 'm',
	65358: 'n',
	65359: 'o',
	65360: 'p',
	65361: 'q',
	65362: 'r',
	65363: 's',
	65364: 't',
	65365: 'u',
	65366: 'v',
	65367: 'w',
	65368: 'x',
	65369: 'y',
	65370: 'z',
}

func removeAccents(s string) string {
	if isASCII(s) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if r < utf8.RuneSelf {
			b.WriteRune(r)
			continue
		}
		if unicode.Is(unicode.Mn, r) || r == 1652 || (r >= 64606 && r <= 64611) {
			continue
		}
		if base, ok := removeOneAccent[r]; ok {
			b.WriteRune(base)
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

func searchSplitRune(r rune) bool {
	if r == 0 || unicode.IsSpace(r) {
		return true
	}
	return strings.ContainsRune(searchWordSplitSet, r)
}

func SearchWords(query string) []string {
	folded := removeAccents(strings.ToLower(strings.TrimSpace(query)))
	return strings.FieldsFunc(folded, searchSplitRune)
}

func dedupWords(words []string) []string {
	seen := make(map[string]struct{}, len(words))
	out := words[:0]
	for _, w := range words {
		if _, dup := seen[w]; dup {
			continue
		}
		seen[w] = struct{}{}
		out = append(out, w)
	}
	return out
}

func NameWords(name, username string) []string {
	folded := removeAccents(name)
	parts := make([]string, 0, 3)
	parts = append(parts, folded)
	if hasRussianLetters(folded) {
		parts = append(parts, translitRusEng(folded))
	}
	if username != "" {
		parts = append(parts, removeAccents(username))
	}
	joined := strings.Join(parts, " ")
	joined += " " + rusKeyboardLayoutSwitch(joined)
	return dedupWords(SearchWords(joined))
}

func MatchesNameWords(index, words []string) bool {
	if len(words) == 0 {
		return true
	}
	for _, w := range words {
		found := false
		for _, nw := range index {
			if strings.HasPrefix(nw, w) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
