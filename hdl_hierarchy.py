import re

class hdl_hierarchy:
    def __init__(self, string, lines, name):
        self.input_hdl = string
        lines[0]-= 1
        self.lines = lines
        self.name=name
        self.selec_hdl = '\n'.join(self.input_hdl.split('\n')[slice(*lines)])
        self.assignemnt_regex = r"\s+(?P<L>[\w\[\]]+)\s+(?:(?:<=)|(?::=)|(?:=))\s+(?P<R>.+);"
        self.right_assignment_variables_regex = r"(?P<V>\b(?<!\')[a-z][0-9a-z\_]+)(?:[\+\*\-\:\w\[\]]+)?"
        self.conditional_regex = r"^\s+(?:(?:(?:else)|(?:begin)|(?:end))\s*){0,2}(?:(?:if|always @)\s*)(?P<R>.*)"
        self.right_conditional_variables_regex = r"(?!begin\b)(?P<V>\b(?<!\')[A-za-z][A-Z0-9a-z\_]+)(?:[\+\*\-\:\w\[\]]+)?"
        self.declaration_regex = r"^\s+(?:(?:input|output|wire|reg|logic|parameter)\s*){1,2}(?P<DB>(?:signed|unsigned)?\s*(?:\[[A-Z0-9a-z\_\-\+\:\s\*]+\])?)\s*(?P<S>[A-Z0-9a-z\_]+)(?P<DA>(?:\s*(?:\[[A-Z0-9a-z\_\-\+\:\s\*\\]+\]))*)?"
        self.left = set()
        self.right = set()
        self.parse_assignments()
        self.parse_conditionals()
        self.only_right = set()
        self.finding_only_right_set()
        self.declarations = {}
        self.parse_declarations()
        self.ports = []
        self.ios = []
        self.generate_ports()

    def parse_assignments(self):
        # filtering assignment lines and capturing left and right sides
        matches = re.finditer(self.assignemnt_regex, self.selec_hdl, re.MULTILINE)
        for match in matches:
            # adding left elements to the left set
            self.left.add(match.groupdict()['L'])
            # filtering variables from right side
            r_matches = re.finditer(self.right_assignment_variables_regex, match.groupdict()['R'], re.MULTILINE)
            for r_match in r_matches:
                # adding right-side variables to right set
                self.right.add(r_match.groupdict()['V'])

    def parse_conditionals(self):
        self.cond_right = []
        # filtering conditional lines and capturing right side
        matches = re.finditer(self.conditional_regex, self.selec_hdl, re.MULTILINE)
        for match in matches:
            # adding left elements to the left set
            r_matches = re.finditer(self.right_conditional_variables_regex, match.groupdict()['R'], re.MULTILINE)
            for r_match in r_matches:
                # adding right-side variables to right set
                self.right.add(r_match.groupdict()['V'])

    def finding_only_right_set(self):
        for m in self.right:
            if m not in self.left:
                self.only_right.add(m)

    def parse_declarations(self):
        # filtering input, output, reg, wire, logic, and parameter declarations
        matches = re.finditer(self.declaration_regex, self.input_hdl, re.MULTILINE)
        for match in matches:
            self.declarations[match.groupdict()['S']] = {'DB':match.groupdict()['DB'], 'DA': match.groupdict()['DA']}

    def generate_ports(self):
        for (io_set, io_type) in ((self.only_right, 'input'), (self.left, 'output logic')):
            for io in io_set:
                declaration = self.declarations.get(io)
                if declaration:
                    self.ports.append(f"{io_type} {declaration['DB']} {io} {declaration['DA']}")
                    self.ios.append(io)
                else:
                    print(f"There is no declaration for variable {io}")

        ports_str = ',\n'.join(self.ports)
        instance_str = ',\n'.join(self.ios)
        module_str = f'//Begin automatic-generated hierarchical module\nmodule {self.name} (\n{ports_str}\n);\n\n{self.selec_hdl}\nendmodule\n//End automatic-generated hierarchical module'
        module_str += '\n' + '\n'.join(self.input_hdl.split('\n')[0:self.lines[0]])
        module_str += '\n\n//Automatic-generated hierarchical module instantiation\n'
        module_str += f'{self.name} {self.name}_inst (\n{instance_str}\n);'
        module_str += '\n\n//End automatic-generated hierarchical module instantiation\n'
        module_str += '\n'.join(self.input_hdl.split('\n')[self.lines[1]:])
        with open(f'{self.name}.sv', 'w') as file:
            file.write(module_str)


if __name__ == "__main__" :
    with open('selection_block.sv','r') as file:
        string = file.read()
    self = hdl_hierarchy(string, [262,265], 'quality')
    #self = hdl_hierarchy(string, [1, 272])
    print('')