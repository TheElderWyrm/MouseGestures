// swiftlint:disable all  — dense table-driven cases ported from the plugins' scratch tests
import XCTest


final class TextOpsTests: XCTestCase {
    private func eq<T: Equatable>(_ a: T, _ b: T, _ n: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, n, file: file, line: line)
    }

    func testTransformations() {
        for (s,e) in [("upper","HELLO WORLD"),("lower","hello world"),("title","Hello World"),("swap","hELLO wORLD")] { eq(TextOps.changeCase("Hello World",style:s),e,"case \(s)") }
        eq(TextOps.changeCase("hello world. this is it! ok",style:"sentence"),"Hello world. This is it! Ok","sentence")
        eq(TextOps.changeCase("some HTTPServer name-here",style:"camel"),"someHttpServerNameHere","camel")
        eq(TextOps.changeCase("some HTTPServer name-here",style:"pascal"),"SomeHttpServerNameHere","pascal")
        eq(TextOps.changeCase("someVariableName",style:"snake"),"some_variable_name","snake")
        eq(TextOps.changeCase("some variable name",style:"kebab"),"some-variable-name","kebab")
        eq(TextOps.changeCase("someVariableName",style:"constant"),"SOME_VARIABLE_NAME","constant")
        eq(TextOps.changeCase("a b\nc d",style:"snake"),"a_b\nc_d","snake multiline")
        eq(TextOps.clean("  a   b  \n\n\n  c  ",operation:"whitespace"),"a b\n\nc","ws")
        eq(TextOps.clean("a  \nb\t\t",operation:"trailing"),"a\nb","trailing")
        eq(TextOps.clean("line one\nline two\n\npara two\nstill",operation:"unwrap"),"line one line two\n\npara two still","unwrap")
        eq(TextOps.clean("<p>Hi <b>there</b> &amp; you</p>",operation:"strip_html"),"Hi there & you","html")
        eq(TextOps.clean("café naïve",operation:"strip_accents"),"cafe naive","accents")
        eq(TextOps.clean("hi 😀 there",operation:"strip_emoji"),"hi  there","emoji")
        eq(TextOps.clean("“hi” — it’s…",operation:"ascii"),"\"hi\" -- it's...","ascii")
        eq(TextOps.smartTypography("He said \"hi\" -- it's 'fine'..."),"He said “hi” – it’s ‘fine’…","smart")
        eq(TextOps.straighten("“a” ‘b’"),"\"a\" 'b'","straighten")
        eq(TextOps.sortLines("pear\nApple\nmango",order:"az"),"Apple\nmango\npear","sort az")
        eq(TextOps.sortLines("pear\nApple\nmango",order:"za"),"pear\nmango\nApple","sort za")
        eq(TextOps.sortLines("10\n9\n100",order:"numeric"),"9\n10\n100","numeric")
        eq(TextOps.sortLines("file10\nfile2\nfile1",order:"natural"),"file1\nfile2\nfile10","natural")
        eq(TextOps.sortLines("ccc\na\nbb",order:"length"),"a\nbb\nccc","length")
        eq(TextOps.editLines("a\nb\na",operation:"dedupe"),"a\nb","dedupe")
        eq(TextOps.editLines("a\n\n  \nb",operation:"remove_blank"),"a\nb","remove_blank")
        eq(TextOps.editLines("a\nb\nc",operation:"reverse"),"c\nb\na","reverse")
        eq(TextOps.editLines("a\nb\nc",operation:"number"),"1. a\n2. b\n3. c","number")
        eq(TextOps.editLines("a\nb\nc",operation:"join_comma"),"a, b, c","join_comma")
        eq(TextOps.editLines("a\nb",operation:"join_space"),"a b","join_space")
        eq(TextOps.editLines("a, b ,c",operation:"split_comma"),"a\nb\nc","split")
        eq(TextOps.editLines("a\n\nb",operation:"indent"),"    a\n\n    b","indent")
        eq(TextOps.editLines("    a\n\tb\n  c",operation:"outdent"),"a\nb\nc","outdent")
        eq(Set(TextOps.editLines("a\nb\nc\nd",operation:"shuffle",seed:7).components(separatedBy:"\n")),Set(["a","b","c","d"]),"shuffle")
        eq(TextOps.prefixSuffix("a\n\nb",prefix:"> ",suffix:";"),"> a;\n\n> b;","prefix")
        for (s,e) in [("double","\"x\""),("paren","(x)"),("bold","**x**"),("backtick","`x`"),("smart_double","“x”")] { eq(TextOps.wrap("x",style:s),e,"wrap \(s)") }
        eq(TextOps.markdown("a\nb",kind:"bullets"),"- a\n- b","bullets")
        eq(TextOps.markdown("a\n\nb",kind:"numbered"),"1. a\n\n2. b","numbered")
        eq(TextOps.markdown("a",kind:"checklist"),"- [ ] a","check")
        eq(TextOps.markdown("a\nb",kind:"quote"),"> a\n> b","quote")
        eq(TextOps.markdown("code",kind:"code_block"),"```\ncode\n```","code")
        eq(TextOps.markdown("T",kind:"h2"),"## T","h2")
        eq(TextOps.markdown("site",kind:"link",url:" https://x.com \n"),"[site](https://x.com)","link")
        eq(TextOps.markdown("- a\n1. b\n> c\n- [x] d",kind:"unlist"),"a\nb\nc\nd","unlist")
        eq(TextOps.encode("a b&c/é",kind:"url_encode"),"a%20b%26c%2F%C3%A9","urlenc")
        eq(TextOps.encode("a%20b%26c",kind:"url_decode"),"a b&c","urldec")
        eq(TextOps.encode("hello",kind:"base64_encode"),"aGVsbG8=","b64")
        eq(TextOps.encode("aGVsbG8=",kind:"base64_decode"),"hello","b64d")
        eq(TextOps.encode("not base64!!",kind:"base64_decode"),nil,"b64 bad")
        eq(TextOps.encode("<a href=\"x\">&</a>",kind:"html_escape"),"&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;","htmlesc")
        eq(TextOps.encode("&lt;b&gt; &amp;amp;",kind:"html_unescape"),"<b> &amp;","htmlunesc")
        eq(TextOps.encode("Hello",kind:"rot13"),"Uryyb","rot13")
        eq(TextOps.encode("abc",kind:"reverse"),"cba","rev")
        eq(TextOps.formatJSON("{\"b\":1,\"a\":[1,2]}",minify:true),"{\"a\":[1,2],\"b\":1}","json min")
        eq(TextOps.formatJSON("{\"a\":1}",minify:false)?.contains("\n"),true,"json pretty")
        eq(TextOps.formatJSON("{bad",minify:false),nil,"json bad")
        eq(TextOps.slugify("Héllo, World! 2026"),"hello-world-2026","slug")
        eq(TextOps.stats("one two three\nfour"),"4 words · 18 characters · 2 lines · under a minute read","stats")
        for (e,v) in [("2+3*4",14.0),("(2+3)*4",20.0),("2^3^2",512.0),("10/4",2.5),("-3+5",2.0),("1,000 + 1",1001.0),("50%",0.5),("10%3",1.0),("2*-3",-6.0),("1.5*2",3.0),("12×3",36.0)] { eq(TextOps.calculate(e),v,"calc \(e)") }
        eq(TextOps.calculate("1/0"),nil,"div0"); eq(TextOps.calculate("abc"),nil,"calc bad"); eq(TextOps.calculate("2+"),nil,"calc incomplete")
        eq(TextOps.formatNumber(2.5),"2.5","fmt"); eq(TextOps.formatNumber(14),"14","fmt int"); eq(TextOps.formatNumber(0.1+0.2),"0.3","fmt float")
        let d=Date(timeIntervalSince1970:1791582174)
        eq(TextOps.renderDate(format:"unix",at:d),"1791582174","unix"); eq(TextOps.renderDate(format:"iso_date",at:d).count,10,"iso")
        eq(TextOps.expand("{date} {clipboard}",at:d,clipboard:"X").hasSuffix(" X"),true,"expand")
        eq(TextOps.lorem(sentences:2).components(separatedBy:". ").count,2,"lorem")
        for (inp,exp) in [("5 km to mi","3.10686 mi"),("70 F to C","21.1111 C"),("2 lb in kg","0.907184 kg"),("1 gal to L","3.78541 L"),("100 mph to km/h","160.934 km/h"),("1 GB to MB","1000 MB"),("90 min to h","1.5 h"),("0 c to F","32 F"),("1,000 m to km","1 km")] { eq(TextOps.convertUnits(inp)?.result,exp,"units \(inp)") }
        eq(TextOps.convertUnits("5 km to kg")==nil,true,"incompatible"); eq(TextOps.convertUnits("hello")==nil,true,"units junk"); eq(TextOps.convertUnits("5 km")==nil,true,"no target")
        eq(TextOps.convertUnits("5 km",target:"m")?.result,"5000 m","explicit target")
        var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(identifier:"UTC")!
        eq(TextOps.convertTimestamp("1791582174",calendar:cal),"2026-10-09 21:42:54","ts sec"); eq(TextOps.convertTimestamp("1791582174000",calendar:cal),"2026-10-09 21:42:54","ts ms")
        eq(TextOps.convertTimestamp("2026-10-09 21:42:54",calendar:cal),"1791582174","ts back"); eq(TextOps.convertTimestamp("2026-10-09",calendar:cal),"1791504000","ts date"); eq(TextOps.convertTimestamp("nope",calendar:cal)==nil,true,"ts junk")

    }
}
