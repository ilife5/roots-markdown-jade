path        = require "path"
jade        = require "jade"
_           = require "lodash"
fs          = require "fs"
minimatch   = require("minimatch")
glob        = require("glob")

module.exports = (opts) ->

  opts = _.defaults opts,
    files: 'docs/**/*.md'
    jade: {}
    indent: "  "
    logo: "logo.png"
    placeholder: "//- {{markdown}}"

  placeholderReg = new RegExp("\\n(([^\\n]*)" + opts.placeholder + ")")

  class MarkdownConversion
    constructor: (@roots) ->
      @category                       = "markdown"
      @layout                         = layout_generate(fs.readFileSync(path.join(@roots.root, opts.layout), "utf-8"))
      @files                          = Array.prototype.concat(opts.files)
      @indent                         = opts.indent
      @jade                           = opts.jade
      @roots.config.locals            ?= {}
      @roots.config.locals.catalog    = {}
      @roots.config.locals.subcatalog = {}
      @catalog                        = catalog_generator(@files, @roots.root)

      if !@jade.basedir
        @jade.basedir = @roots.root

    fs: ->
      extract: true
      detect: (f) =>
        _.some(@files, minimatch.bind(@, f.relative))

    compile_hooks: ->
      before_file: before_hook.bind(@)
      write: write_hook.bind(@)

    ###**
     * generate layout content, calculate the indent and index
    ###
    layout_generate= (layout) ->
      regResult = layout.match(placeholderReg)

      if regResult
        layout: layout.replace(regResult[1], "")
        indent: regResult[2]
        index : regResult.index + 1

    ###**
     * pipe ctx.content before file
     * save path information
     * save catalog information
    ###
    before_hook= (ctx) ->
      @roots.config.locals.catalog = @catalog
      @roots.config.locals.subcatalog = _.defaults {}, @catalog[get_catalog(ctx.file_options._path)]
      delete @roots.config.locals.subcatalog.defaultPage
      @md_content = ctx.content

    ###**
     * generate content use jade and write
    ###
    write_hook= (ctx) ->
      if @layout and path.normalize(ctx.file_options._path).split(path.sep).length > 3
        content = @md_content.replace(/([^\n]+)/g, @layout.indent + @indent + "$1")
        content = @layout.layout.substring(0, @layout.index) + @layout.indent + ":markdown\n" + content + @layout.layout.substring(@layout.index)
        fn = jade.compile content, @jade
        path: path.join(ctx.roots.root, ctx.file_options._path)
        content: fn(ctx.roots.config.locals)
      else
        true

    get_catalog= (_path) ->
      path.normalize(_path).split(path.sep)[2]

    logo_get= (_path) ->
      _logo = null
      _.each Array.prototype.concat(opts.logo), (logo) ->
        _logo = glob.sync(path.join(_path, logo).replace(/(\[|\])/g, "\\$1"))[0]
        if _logo
          false
      _logo

    seq_literate= (obj) ->
      if !obj.seq
        return
      else
        _.each obj.seq, (seq) ->

          if obj[seq]
            seq_literate obj[seq]

        obj.seq = seq_sort obj.seq

    seq_sort= (seq) ->
      seqPreffix = /\[(\d+)\]_/

      _.map seq, (val, index) ->

        result = val.match seqPreffix
        order = null

        if result
          order = result[1]

        index: index
        name: val
        order: order

      .sort (a, b) ->
        if a.order and b.order
          return a.order - b.order
        else if a.order
          return -1
        else if b.order
          return 1
        else
          return a.index - b.index

      .map (val) ->
        display: val.name.replace(seqPreffix, "")
        name: val.name

    catalog_generator= (files, root)->

      catalog =
        seq: []
      defaultSuffix = "_DEFAULT"

      _.each Array.prototype.concat(files), (pattern) ->
        _.each glob.sync(pattern), (file) ->

          _name = path.basename file, ".md"
          _path = path.normalize(file.replace ".md", ".html")
          _catalogs = _path.split(path.sep).slice(1)
          _parentsPath = _path.split(path.sep)[0]
          _current = catalog

          ### catalog ###
          if _catalogs.length is 1
            _catalog = _name.replace defaultSuffix, ""
            _current.seq.push _name
            _current[_catalog] =
              defaultPage: fs.readFileSync( path.join(root, file), "utf-8" )


          while _catalogs.length > 1
            _catalog = _catalogs.shift()
            _parentsPath += "/" + _catalog
            _current.seq = _.union _current.seq, [_catalog]
            _current[_catalog] ?= {}
            _current[_catalog].seq ?= []
            if logo_get(_parentsPath)
              _current[_catalog].logo = "/" + logo_get(_parentsPath)

            if _name.match(defaultSuffix) or !_current[_catalog].defaultPage
              _current[_catalog].defaultPage = "/" + _path

            _name = _name.replace defaultSuffix, ""

            if _catalogs.length is 1
              _current[_catalog].seq.push _name
              _current[_catalog][_name] = "/" + _path
            else
              _current = _current[_catalog]

      seq_literate(catalog)
      catalog