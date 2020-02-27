const fs = require('fs');
const parse = require('csv-parse/lib/sync');

function runElm(spec, records){
    var app = require('tsformula_elm_parser.js')
        .Elm.FormulaParserValidation.Main.init({
            flags: [spec, records]
        });
    console.log('DONE');
}

require("yargs")
    .scriptName("tsformula-elm-parser")
    .usage('$0 <cmd> [args]')
    .env('TSFORMULA_ELM_PARSER')
    .option('spec', {
        alias: 's',
        demandOption: true,
        describe: 'JSON specification file',
        coerce: (x) => { return JSON.parse(fs.readFileSync(x)) }
    })
    .command(
        'parse [catalog]',
        'Parse formula CSV with name, code header',
        (yargs) => {
            yargs.positional('catalog', {
                type: 'string',
                describe: 'CSV formula catalog'
            })
        },
        (args) => {
            const records = parse(
                fs.readFileSync(args.catalog, 'utf8'),
                {columns: true, quote: "'"}
            );
            runElm(args.spec, records);
        }
    )
    .help()
    .argv
