#!/usr/bin/coffee
yaml = require 'js-yaml'
fs   = require 'fs'
glob = require 'glob'
_    = require 'underscore'



if process.argv.length < 4
    throw new Error "invocation: #{process.argv[0]} #{process.argv[1]} hiera.yaml hieradir.."

hierayaml = process.argv[2]
hieradirs = process.argv[3...]



if not Array.prototype.includes
    Array.prototype.includes = (needle) ->
        (this.indexOf needle) >= 0

arrayExcept = (a, i) ->
    [].concat a[...i], a[i+1..]

permute = (a) ->
    return [[]] if a.length is 0
 
    [].concat (for v, i in a
        [v].concat perm for perm in permute arrayExcept a, i)...
 
count = 0

fs.readFile 'hiera.yaml', (err, filedata) =>
    throw err if (err)
    doc = yaml.safeLoad filedata
    console.log doc

    hier = doc[':hierarchy']

    data = {}

    console.log "detecting facts"
    for path in hier

        tmppath = path.replace /%\{[^\}]*\}/g, '*'
        pathregex = new RegExp (path.replace /%\{[^\}]*\}/g, '([^/]*)')+'.yaml'
        facts = path.match /%\{[^\}]*\}/g
        facts ?= []

        facts = (fact.replace /%{(::)?([^\}]*)}/, '$2' for fact in facts)

        matches = []
        for dir in hieradirs
            matches = matches.concat glob.sync dir+'/'+tmppath+'.yaml'
        for match in matches
            pathmatches = (match.match pathregex)[1..]

            d = try
                    yaml.safeLoad fs.readFileSync match
                catch e
                    console.log match+' error'
                    null

            m = 
                file: match
                facts: []
            for fact, i in facts
                m.facts[fact] = pathmatches[i]

            for own k, v of d
                data[k] ?=
                    byFact: {}
                    byValue: {}
                o = 
                    value: v
                    meta: m
                if v instanceof Object
                    data[k].byValue._obj ?= []
                    data[k].byValue._obj.push o
                else
                    data[k].byValue[v] ?= []
                    data[k].byValue[v].push o

                for permutation in permute [0..facts.length][...-1]
                    base = data[k].byFact
                    for key in permutation
                        fact = facts[key]
                        value = pathmatches[key]
                        base[fact] ?= {}
                        base[fact][value] ?= {}
                        base = base[fact][value]
                    if base._data?
                        console.log "overriding #{k} from diferent file"
                    base._data = o


    for own k, d of data
        keys = Object.keys(d.byValue)
        if keys.length is 1 and not d.byValue._obj
            if d.byValue[keys[0]].length > 1
                console.log "only one value: #{k}: #{keys[0]}"
                console.log "  set #{d.byValue[keys[0]].length} times:"
                for val in d.byValue[keys[0]]
                    console.log "    #{val.meta.file}"
                count++
                null
        else
            check = (data, parval, path = [])->
                myval = parval

                fact = path?[-1]?.fact
                factval = path?[-1]?.value
                if data._data?
                    myval = data._data
                    if data._data.value is parval?.value
                        console.log "override #{k} with same as parrent, fact #{path[path.length-1].fact}: #{path[path.length-1].value}"
                        count++

                for f, x of data when f[0] isnt '_'
                    commonv = null
                    common = true
                    commoncount = 0
                    for fval, d of x
                        p = path.slice()
                        p.push
                            fact: f
                            value: fval
                        retv = check d, myval, p
                        if commonv? and commonv isnt retv?.value
                            common = false
                        else if not commonv?
                            commonv = retv?.value
                            commoncount++
                        else
                            commoncount++
                    if common and commonv? and commoncount > 1
                        console.log "#{k}: #{commonv} for #{commoncount} values of #{f} "
                        console.log path unless path.length is 0
                        count++

                myval
            check d.byFact, null

    console.log ""
    console.log "found #{count} potential issues"