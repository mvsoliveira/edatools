from flask import Flask, render_template, request
from urllib.parse import unquote
from pygments import highlight
from pygments.lexers.hdl import VhdlLexer
from pygments.formatters import HtmlFormatter
import re
import pandas as pd

regex = r"((?P<A>^\s*(?P<AS>[\w\.\,\(\s\)]+)\s[<:]=\s*)?($\s*)?(?P<whenelse>\s*(?P<V>[\w\.\,\(\s\)]+)\s+when\s+(?P<VC>[\w\.\,\(\s\)]+)=\s+\"(?P<C>\w+)\"\s+else\s*$))|(?P<else>^\s*(?P<Ve>[\w\.\,\(\s\)]+)\s*;\s*$)"

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

def debug_matches(string):
    matches = re.finditer(regex, string, re.MULTILINE)
    df = pd.DataFrame()
    for matchNum, match in enumerate(matches, start=1):
        df = df.append(pd.DataFrame(match.groupdict(), index=[matchNum]))

    return df.to_html()

def formatter(string):
    html = highlight(string, VhdlLexer(), HtmlFormatter(full=True))
    return html

def whenelse(string):
    matches = re.finditer(regex, string, re.MULTILINE)
    outs = ""
    for match in matches:
        mdict = match.groupdict()
        if mdict['A']:
            signal = mdict['A'].strip()
            outs += f"case {mdict['VC'].strip()} is\n"
        if mdict['C']:
            outs += f"    when \"{mdict['C']}\" => {signal} {mdict['V'].strip()};\n"
        if mdict['Ve']:
            outs += f"    when others => {signal} {mdict['Ve'].strip()};\nend case;\n\n"
    html = formatter(outs)
    return html

funcs = {
    'debug': debug_matches,
    'formatter' : formatter,
    'whenelse' : whenelse,
}

@app.route('/edatools')
def edatools():
    text = request.args.get('jsdata')
    mode = request.args.get('jsmode')
    string = unquote(text)
    return funcs[mode](string)


if __name__ == '__main__':
    app.run(debug=True)
