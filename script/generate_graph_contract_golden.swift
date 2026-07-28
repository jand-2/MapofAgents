import Foundation
import MapofAgentsCore

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: graph-contract-golden <input.json> <output.json>\n".utf8)
    )
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let decoder = JSONDecoder()
MapofAgentsJSONCoding.configureContractDates(on: decoder)
let graph = try decoder.decode(AgentGraph.self, from: Data(contentsOf: inputURL))

let encoder = JSONEncoder()
MapofAgentsJSONCoding.configureContractDates(on: encoder)
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(graph).write(to: outputURL, options: .atomic)
