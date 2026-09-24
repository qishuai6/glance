import Foundation

/// 语言定义：关键字表 + 注释规则，驱动通用高亮引擎。
struct Lang {
    let name: String
    let keywords: Set<String>
    let lineComments: [String]
    let blockComment: (String, String)?
    /// 额外着色：类型风格词（可选）
    let types: Set<String>

    static let none = Lang(name: "", keywords: [], lineComments: [], blockComment: nil, types: [])

    static let table: [String: Lang] = {
        var t: [String: Lang] = [
            "sql": Lang(
                name: "SQL",
                keywords: Set("select from where insert into values update set delete create table drop alter index view join left right inner outer on group by order having limit offset union all distinct as and or not null primary key foreign references default auto_increment if exists case when then else end like in between is count sum avg min max varchar integer int bigint boolean text date timestamp decimal asc desc truncate begin commit rollback transaction unique check cascade add column procedure trigger".split(separator: " ").map(String.init)),
                lineComments: ["--"], blockComment: ("/*", "*/"), types: Set()),
            "swift": Lang(
                name: "Swift",
                keywords: Set("func let var if else guard switch case default for while repeat do try catch throw throws rethrows defer class struct enum protocol extension typealias init deinit static private public internal fileprivate open final override self super nil true false where associatedtype actor async await some any inout mutating nonmutating lazy weak unowned return break continue fallthrough import as is in operator subscript willSet didSet indirect".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"),
                types: Set("Int Double Float Bool String Character Array Dictionary Set Optional Result Codable Identifiable View".split(separator: " ").map(String.init))
                    .union((65...90).map { String(UnicodeScalar($0)) })),
            "py": Lang(
                name: "Python",
                keywords: Set("def class if elif else for while break continue pass import from as return yield lambda try except finally raise with global nonlocal assert del in is not and or None True False async await match case".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "js": Lang(
                name: "JavaScript",
                keywords: Set("function var let const if else for while do switch case default break continue return class extends super new this typeof instanceof in of try catch finally throw async await yield import export from as delete void null undefined true false static get set".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "ts": Lang(
                name: "TypeScript",
                keywords: Set("function var let const if else for while do switch case default break continue return class extends super new this typeof instanceof in of try catch finally throw async await yield import export from as delete void null undefined true false static get set interface type enum implements private public protected readonly namespace declare abstract satisfies keyof infer never unknown any string number boolean".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "go": Lang(
                name: "Go",
                keywords: Set("func package import var const type struct interface map chan go defer select switch case default if else for range return break continue fallthrough goto nil true false make new len cap append copy".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "rs": Lang(
                name: "Rust",
                keywords: Set("fn let mut const static struct enum trait impl for while loop if else match use pub mod crate self super where as in ref move async await dyn box return break continue true false".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"),
                types: Set("Some None Ok Err Vec String HashMap Option Result Box Rc Arc".split(separator: " ").map(String.init))),
            "java": Lang(
                name: "Java",
                keywords: Set("public private protected static final void int long double float boolean char byte short class interface enum extends implements import package new this super return if else for while do switch case default try catch finally throw throws abstract synchronized volatile transient native assert instanceof null true false record var".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "c": Lang(
                name: "C",
                keywords: Set("int char long short float double void unsigned signed struct union enum typedef static extern const volatile register return if else for while do switch case default break continue goto sizeof auto inline restrict nullptr NULL true false define include ifndef endif pragma".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "cpp": Lang(
                name: "C++",
                keywords: Set("int char long short float double void unsigned signed struct union enum typedef static extern const volatile return if else for while do switch case default break continue goto sizeof auto inline public private protected class new delete this virtual override template typename namespace using try catch throw operator friend mutable explicit constexpr nullptr NULL true false include define ifndef endif pragma".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "m": Lang(
                name: "Objective-C",
                keywords: Set("int char long short float double void unsigned signed struct enum typedef static extern const return if else for while do switch case default break continue id YES NO nil Nil self super @interface @implementation @property @end @class @protocol @selector @try @catch @finally @throw @synchronized strong weak copy nonatomic atomic readonly alloc init new".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "rb": Lang(
                name: "Ruby",
                keywords: Set("def end class module if elsif else unless while until for do begin rescue ensure raise return yield self nil true false require require_relative attr_accessor puts lambda proc then case when and or not".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "php": Lang(
                name: "PHP",
                keywords: Set("function class interface extends implements public private protected static final abstract new return if else elseif while for foreach as break continue switch case default try catch finally throw echo print require include require_once include_once namespace use const null true false global isset unset match enum readonly".split(separator: " ").map(String.init)),
                lineComments: ["//", "#"], blockComment: ("/*", "*/"), types: Set()),
            "kt": Lang(
                name: "Kotlin",
                keywords: Set("fun val var if else for while when class object interface enum data sealed open override private public internal protected import package return break continue try catch finally throw is as in null true false this super companion lateinit const suspend".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "lua": Lang(
                name: "Lua",
                keywords: Set("function end local if then else elseif for while do return break repeat until nil true false and or not".split(separator: " ").map(String.init)),
                lineComments: ["--"], blockComment: ("--[[", "]]"), types: Set()),
            "pl": Lang(
                name: "Perl",
                keywords: Set("sub my our local if elsif else unless while until for foreach do last next redo return use require package print printf say defined exists delete grep map sort keys values each push pop shift unshift".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "sh": Lang(
                name: "Shell",
                keywords: Set("if then else elif fi for while do done case esac function return exit local export echo read set shift until in source alias unset trap".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "css": Lang(
                name: "CSS",
                keywords: Set(),
                lineComments: [], blockComment: ("/*", "*/"), types: Set()),
            "xml": Lang(name: "XML", keywords: Set(), lineComments: [], blockComment: nil, types: Set()),
            "plist": Lang(name: "plist", keywords: Set(), lineComments: [], blockComment: nil, types: Set()),
            "s": Lang(
                name: "Assembly",
                keywords: Set("mov push pop add sub mul div jmp je jne call ret lea cmp int section global extern".split(separator: " ").map(String.init)),
                lineComments: [";", "#"], blockComment: nil, types: Set()),
            "make": Lang(
                name: "Makefile",
                keywords: Set("all clean install ifeq ifneq endif include export".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "r": Lang(
                name: "R",
                keywords: Set("function if else for while repeat library require data frame list c return TRUE FALSE NULL NA Inf next break source install.packages suppressMessages mutate filter select group_by summarise".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "scala": Lang(
                name: "Scala",
                keywords: Set("object class trait case def val var implicit lazy sealed abstract extends with override final private protected import package match yield for while if else try catch finally throw return type new this super null true false".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "dart": Lang(
                name: "Dart",
                keywords: Set("void var final const late class abstract extends implements mixin with async await Future Stream List Map Set String int double bool num dynamic null true false if else for while switch case default return import library part new this super try catch finally throw enum factory static get set".split(separator: " ").map(String.init)),
                lineComments: ["//"], blockComment: ("/*", "*/"), types: Set()),
            "ex": Lang(
                name: "Elixir",
                keywords: Set("def defmodule defp defstruct defprotocol defimpl do end case cond with import require alias use receive send spawn link if unless for when and or not nil true false fn".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: nil, types: Set()),
            "ps1": Lang(
                name: "PowerShell",
                keywords: Set("function param begin process end filter if elseif else switch foreach for while do until break continue return try catch finally throw trap class enum interface using local global static param default valuefrompipeline".split(separator: " ").map(String.init)),
                lineComments: ["#"], blockComment: ("<#", "#>"), types: Set()),
            "bat": Lang(
                name: "Batch",
                keywords: Set("echo off set setlocal endlocal if exist goto call exit for do in rem pause cls del copy move md rd start title".split(separator: " ").map(String.init)),
                lineComments: ["REM ", "::"], blockComment: nil, types: Set()),
            "tex": Lang(
                name: "LaTeX",
                keywords: Set("documentclass usepackage begin end section subsection subsubsection title author date item ref cite label equation figure table tabular itemize enumerate align newcommand renewcommand frac sum int".split(separator: " ").map(String.init)),
                lineComments: ["%"], blockComment: nil, types: Set()),
        ]
        // 别名（不能在字面量里引用 table 自身）
        t["h"] = t["c"]
        t["cc"] = t["cpp"]
        t["cxx"] = t["cpp"]
        t["hpp"] = t["cpp"]
        t["bash"] = t["sh"]
        t["zsh"] = t["sh"]
        t["jsx"] = t["js"]
        t["mjs"] = t["js"]
        t["cjs"] = t["js"]
        t["tsx"] = t["ts"]
        t["exs"] = t["ex"]
        t["cmd"] = t["bat"]
        t["vue"] = Lang(name: "Vue", keywords: Set(), lineComments: [], blockComment: nil, types: Set())
        t["svelte"] = t["vue"]
        return t
    }()

    /// 扩展名 → 语言键
    static func langKey(forExt ext: String) -> String? {
        let known = ["sql","swift","py","js","ts","go","rs","java","c","h","cpp","cc","cxx","hpp","m",
                     "rb","php","kt","lua","pl","sh","bash","zsh","css","xml","plist","s","make",
                     "json","jsonl","ndjson","yaml","yml","toml","ini","conf","cfg","env","properties","log",
                     "csv","tsv","md","markdown","zip","tar","tgz"]
        return known.contains(ext) ? ext : nil
    }
}
