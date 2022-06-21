from flask import Flask, render_template, request
from urllib.parse import unquote
from pygments import highlight
from pygments.lexers.hdl import VhdlLexer, SystemVerilogLexer
from pygments.formatters import HtmlFormatter
from hdl_hierarchy import hdl_hierarchy
import re
import pandas as pd

regex = r"((?P<A>^\s*(?P<AS>[\w\.\,\(\s\)]+)\s[<:]=\s*)?($\s*)?(?P<whenelse>\s*(?P<V>[\w\.\,\(\s\)]+)\s+when\s+(?P<VC>[\w\.\,\(\s\)]+)=\s+\"(?P<C>\w+)\"\s+else\s*$))|(?P<else>^\s*(?P<Ve>[\w\.\,\(\s\)]+)\s*;\s*$)"

app = Flask(__name__)

@app.route('/utils', methods=['GET', 'POST'])
def index():
    return render_template('index.html')

@app.route('/', methods=['GET', 'POST'])
def verilog():
    return render_template('verilog.html')


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
    signal = ""
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

@app.route('/edatools', methods=['GET', 'POST'])
def edatools():
    text = request.form['jsdata']
    mode = request.form['jsmode']
    string = unquote(text)
    return funcs[mode](string)

@app.route('/verilog_processing', methods=['GET', 'POST'])
def verilog_processing():
    code = request.form['jscode']
    lines = request.form['jslines']
    name = request.form['jsname']
    code_string = unquote(code)
    code_lines = unquote(lines)
    code_name = unquote(name)
    lines_list = ([int(i) for i in code_lines.split('-')])
    hier = hdl_hierarchy(code_string, lines_list, code_name, generate_file=False)
    html = highlight(hier.module_str, SystemVerilogLexer(), HtmlFormatter(full=True))
    return hier.debug_html+html

if __name__ == '__main__':
    try:
        import googleclouddebugger

        googleclouddebugger.enable(
            breakpoint_enable_canary=True
        )
    except ImportError:
        pass

    app.run(debug=True)
