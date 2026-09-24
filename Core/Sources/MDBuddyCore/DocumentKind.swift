import Foundation

/// What kind of preview a file gets.
public enum DocumentKind: Equatable {
    case markdown
    /// Source code; `language` is a highlight.js language name, or nil to auto-detect.
    case code(language: String?)
    case plainText

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext", "mdtxt", "rmd", "qmd",
    ]

    static let plainTextExtensions: Set<String> = ["txt", "text", "log", "out", "rtx", ""]

    /// Chooses a preview style from the file name (extension, or well-known file names).
    public static func detect(fileName: String) -> DocumentKind {
        let name = (fileName as NSString).lastPathComponent
        var ext = (name as NSString).pathExtension.lowercased()
        // Foundation reports no extension for dotfiles (".gitignore"); use the name after the dot.
        if ext.isEmpty, name.hasPrefix("."), name.count > 1 { ext = String(name.dropFirst()).lowercased() }
        if markdownExtensions.contains(ext) { return .markdown }
        if let language = LanguageMap.byFileName[name.lowercased()] { return .code(language: language) }
        if let language = LanguageMap.byExtension[ext] { return .code(language: language) }
        if plainTextExtensions.contains(ext) { return .plainText }
        return .code(language: nil)
    }
}

/// Maps file extensions / names to highlight.js language identifiers.
/// Every value must be a language present in the bundled highlight.js build.
public enum LanguageMap {
    public static let byExtension: [String: String] = {
        var map: [String: String] = [:]
        let table: [(String, [String])] = [
            ("bash", ["sh", "bash", "zsh", "ksh", "command", "bashrc", "zshrc", "profile"]),
            ("c", ["c", "h"]),
            ("cpp", ["cc", "cpp", "cxx", "c++", "hh", "hpp", "hxx", "h++", "ino", "cu", "cuh"]),
            ("csharp", ["cs", "csx"]),
            ("css", ["css"]),
            ("diff", ["diff", "patch"]),
            ("go", ["go"]),
            ("graphql", ["graphql", "gql"]),
            ("ini", ["ini", "cfg", "conf", "toml", "properties", "editorconfig", "gitconfig", "desktop"]),
            ("java", ["java", "jsp"]),
            ("javascript", ["js", "mjs", "cjs", "jsx"]),
            ("json", ["json", "jsonc", "json5", "geojson", "ipynb", "webmanifest", "babelrc", "eslintrc"]),
            ("kotlin", ["kt", "kts"]),
            ("less", ["less"]),
            ("lua", ["lua"]),
            ("makefile", ["mk", "mak", "make"]),
            ("objectivec", ["m", "mm"]),
            ("perl", ["pl", "pm", "t"]),
            ("php", ["php", "phtml"]),
            ("python", ["py", "pyw", "pyi", "pyx", "pxd", "gyp", "wsgi"]),
            ("r", ["r"]),
            ("ruby", ["rb", "rake", "gemspec", "podspec", "ru"]),
            ("rust", ["rs"]),
            ("scss", ["scss", "sass"]),
            ("sql", ["sql", "psql", "ddl"]),
            ("swift", ["swift"]),
            ("typescript", ["ts", "tsx", "mts", "cts"]),
            ("vbnet", ["vb", "vbs"]),
            ("wasm", ["wat", "wast"]),
            ("xml", ["xml", "html", "htm", "xhtml", "svg", "plist", "xsd", "xsl", "xslt", "rss", "atom",
                     "storyboard", "xib", "csproj", "vcxproj", "entitlements", "vue", "svelte"]),
            ("yaml", ["yaml", "yml", "cff"]),
            // Languages from the extra bundle (highlight-extra.min.js)
            ("matlab", ["matlab"]),
            ("julia", ["jl"]),
            ("latex", ["tex", "sty", "cls", "bib", "ltx", "dtx", "bbl"]),
            ("dockerfile", ["dockerfile"]),
            ("cmake", ["cmake"]),
            ("powershell", ["ps1", "psm1", "psd1"]),
            ("scala", ["scala", "sc", "sbt"]),
            ("haskell", ["hs", "lhs"]),
            ("elixir", ["ex", "exs"]),
            ("dart", ["dart"]),
            ("fortran", ["f", "for", "f77", "f90", "f95", "f03", "f08"]),
            ("protobuf", ["proto"]),
            ("nginx", ["nginx"]),
            ("clojure", ["clj", "cljs", "cljc", "edn"]),
            ("erlang", ["erl", "hrl"]),
            ("ocaml", ["ml", "mli"]),
            ("groovy", ["groovy", "gradle"]),
            ("vim", ["vim", "vimrc"]),
            ("applescript", ["applescript", "scpt"]),
            ("plaintext", ["csv", "tsv", "gitignore", "gitattributes", "dockerignore", "npmrc", "env"]),
        ]
        for (language, extensions) in table {
            for ext in extensions { map[ext] = language }
        }
        return map
    }()

    /// Extension-less files recognised by name.
    public static let byFileName: [String: String] = [
        "makefile": "makefile", "gnumakefile": "makefile",
        "dockerfile": "dockerfile", "containerfile": "dockerfile",
        "cmakelists.txt": "cmake",
        "gemfile": "ruby", "rakefile": "ruby", "podfile": "ruby", "brewfile": "ruby", "vagrantfile": "ruby",
        ".bashrc": "bash", ".zshrc": "bash", ".bash_profile": "bash", ".zprofile": "bash", ".profile": "bash",
        ".vimrc": "vim", ".gitconfig": "ini", ".editorconfig": "ini",
        "package.swift": "swift",
    ]
}
