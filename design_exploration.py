import re
import pandas as pd

class design_exploration:
    def __init__(self, string):
        self.input_hdl = string
        self.ports_regex = r"^\s*(?P<D>(?:input|output))\s*(?P<DB>(?:signed|unsigned)?\s*(?:\[[A-Z0-9a-z\_\-\+\:\s\*]+\])?)\s*(?P<S>[A-Z0-9a-z\_]+)(?P<DA>(?:\s*(?:\[[A-Z0-9a-z\_\-\+\:\s\*\\]+\]))*)?"
        self.name_regex = r"^\s*module\s+(?P<N>[\w\d]+)\s*\("
        self.parse_name()
        self.parse_ports()
        self.extract_clocks()
        self.generate_registers()
        self.generate_assignments()
        self.generate_instantiation()
        self.generate_module()

    def parse_ports(self):
        self.ports = {}
        self.port_decl = []
        self.debug_p = []
        # filtering port declarations and detecting directions, names, and sizes
        matches = re.finditer(self.ports_regex, self.input_hdl, re.MULTILINE)
        for matchNum, match in enumerate(matches, start=1):
            self.ports[match.groupdict()['S']] = {'D': match.groupdict()['D'], 'DB': match.groupdict()['DB'], 'DA':match.groupdict()['DA']}
            self.debug_p.append(pd.DataFrame(match.groupdict(), index=[matchNum]))
            self.port_decl.append(f"{match.groupdict()['D']} logic {match.groupdict()['DB']} {match.groupdict()['S']} {match.groupdict()['DA']}")
        self.debug_html = pd.concat(self.debug_p).to_html()

    def parse_name(self):
        matches = re.finditer(self.name_regex, self.input_hdl, re.MULTILINE)
        self.name = next(matches).groupdict()['N']

    def extract_clocks(self):
        self.clocks=[]
        for p in self.ports:
            if any((s in p for s in ('clock','clk'))):
                self.clocks.append(p)
        for c in self.clocks:
            self.ports.pop(c)

    def generate_registers(self):
        self.regs_decl = []
        for (key, value) in self.ports.items():
            self.regs_decl.append(f"reg {value['DB']} {key}_reg {value['DA']}")

    def generate_assignments(self):
        self.assignments = []
        for (key, value) in self.ports.items():
            if value['D'] == 'input':
                self.assignments.append(f"{key}_reg <= {key}")
            else:
                self.assignments.append(f"{key} <= {key}_reg")

    def generate_instantiation(self):
        self.instantiation = []
        for c in self.clocks:
            self.instantiation.append(f".{c}({c})")
        for (key, value) in self.ports.items():
            self.instantiation.append(f".{key}({key}_reg)")


    def generate_module(self):
        self.output_hdl = '// Automatic generated design exploration module\n'
        if not self.clocks:
            self.port_decl.append('input logic clk')

        self.output_hdl += f'module {self.name}_de (\n' + ',\n'.join(self.port_decl) + '\n);\n\n'
        self.output_hdl += '// Registers declaration\n' + ';\n'.join(self.regs_decl)+';\n\n'
        if not self.clocks:
            self.clocks.append('clk')
            self.output_hdl += f'// No clock was found in the input source file, clock clk has been added to exploration wrapper\n'

        for c in self.clocks:
            self.output_hdl += f'// Registering interface signals for clock {c}\n'
            self.output_hdl += f'always @ (posedge {c}) begin\n    '
            self.output_hdl += f';\n    '.join(self.assignments)+';\n'
            self.output_hdl += f'end // always @ (posedge {c})\n\n'
        self.output_hdl += f'// Instantiating design {self.name}\n'
        self.output_hdl += f'{self.name} {self.name}_inst (\n'
        self.output_hdl += ',\n'.join(self.instantiation)+'\n);\n'
        self.output_hdl += f'\nendmodule // {self.name}_de'

if __name__ == '__main__':
    string = open('test.v', 'r').read()
    print(string)
    de = design_exploration(string)
    print(de.output_hdl)

