// Swift Playground
import UIKit

protocol FormModelValue {
    
    mutating func set(_ any: Any?) throws
    var value: Any? { get }
    
}

protocol FormModel {
    
    associatedtype Key : Hashable
    associatedtype Value : FormModelValue
    
    mutating func set(_ any: Any?, for key: Key) throws
    func value(for key: Key) -> Any?
    
}

protocol OrderedKeysFormModel : FormModel {
    
    var orderedKeys: [Key] { get }
    
}

enum ValidationResult {
    case valid
    case notValid(reasons: [String])
    
    var reasons: [String] {
        if case .notValid(reasons: let reasons) = self {
            return reasons
        }
        return []
    }
}

struct ValidationResultError : Error {
    var reasons: [String]
    init?(_ validationResult: ValidationResult) {
        if validationResult.reasons.isEmpty {
            return nil
        }
        self.reasons = validationResult.reasons
    }
}

extension ValidationResult {
    
    static func combine(lhs: ValidationResult, rhs: ValidationResult) -> ValidationResult {
        return lhs.and(rhs)
    }
    
    func and(_ other: ValidationResult) -> ValidationResult {
        switch (self, other) {
        case (.valid, .valid):
            return .valid
        default:
            return .notValid(reasons: self.reasons + other.reasons)
        }
    }
    
}

protocol ValidatingValuesFormModel : FormModel {
    
    func validate(_ key: Key) -> ValidationResult
    
}

protocol ValidatingModelFormModel : FormModel {
    
    func validateModel() -> ValidationResult
    
}

protocol DictionaryBasedFormModel : FormModel {
    
    var fields: [Key : Value] { get set }
    
}

struct Validator {
    
    var isNilValid: Bool
    private let _validate: (Any) -> ValidationResult
    
    init(_ validate: @escaping (Any) -> ValidationResult, isNilValid: Bool = true) {
        self._validate = validate
        self.isNilValid = isNilValid
    }
    
//    func validate(_ value: T?) -> ValidationResult {
//        if let value = value {
//            return _validate(value)
//        } else {
//            return validateNil()
//        }
//    }
    
    func validateNil() -> ValidationResult {
        return isNilValid ? .valid : .notValid(reasons: ["No value"])
    }
    
    func validate(_ value: Any?) -> ValidationResult {
        if let value = value {
            return _validate(value)
        } else {
            return validateNil()
        }
    }
    
}

extension DictionaryBasedFormModel where Self : OrderedKeysFormModel {
    
    var orderedValues: [Value] {
        return orderedKeys.flatMap({ fields[$0] })
    }
    
}

extension DictionaryBasedFormModel {
    
    func value(for key: Key) -> Any? {
        return fields[key]?.value
    }
    
    mutating func set(_ any: Any?, for key: Key) throws {
        try fields[key]?.set(any)
    }
    
}

enum AModelKeys {
    case name, age, gender
}

enum Gender : String {
    case male = "Male"
    case female = "Female"
}

enum BasicModelValue : FormModelValue {
    
    enum InputType {
        case string, integer, floating
    }
    
//    case string(String)
    case textInput(String?, of: InputType)
    case selection([String], selected: Int?, placeholder: String?)
    
    enum Error : Swift.Error {
        case wrongType
    }
    
    mutating func set(_ any: Any?) throws {
        switch self {
        case .textInput(_, let inputType):
            if let string = any as? String {
                self = .textInput(string, of: inputType)
                return
            }
        case .selection(let selection, _, let placeholder):
            if let int = any as? Int? {
                self = .selection(selection, selected: int, placeholder: placeholder)
                return
            }
        }
        throw Error.wrongType
    }
    
    var value: Any? {
        switch self {
        case .textInput(let string, _):
            return string
        case .selection(_, selected: let selected, placeholder: _):
            return selected
        }
    }
    
}

var some = BasicModelValue.selection([Gender.male.rawValue, Gender.female.rawValue], selected: 0, placeholder: "Select Gender")
try! some.set(2)
some

struct AModel : OrderedKeysFormModel, ValidatingValuesFormModel, ValidatingModelFormModel, DictionaryBasedFormModel {
    
    typealias Key = AModelKeys
    typealias Value = BasicModelValue
    
    var fields: [AModelKeys : BasicModelValue] = [
        .name: .textInput(nil, of: .string),
        .age: .textInput(nil, of: .integer),
        .gender: .selection([Gender.male.rawValue, Gender.female.rawValue], selected: nil, placeholder: "Select Gender"),
    ]
    
    let orderedKeys: [AModelKeys] = [.name, .age, .gender]
    
    func validate(_ key: AModelKeys) -> ValidationResult {
        switch key {
        case .age:
            if let strAge = value(for: .age) as? String, let _ = Int(strAge) {
                return .valid
            }
            return .notValid(reasons: ["Cannot convert string to int"])
        default:
            return .valid
        }
    }
    
    func validateModel() -> ValidationResult {
        return orderedKeys.map(self.validate).reduce(.valid, ValidationResult.combine)
    }
    
}

var model = AModel()

try! model.set("Alba", for: .name)
print(model.orderedValues)
try! model.set("15a", for: .age)
model.validateModel()
model.validate(.age)

try! model.set("15", for: .age)
model.validateModel()

struct Row<Identifier : Hashable, Content> {
    let identifier: Identifier
    var content: Content
}

protocol FormViewModelProtocol {
    
    associatedtype RowIdentifier : Hashable
    associatedtype RowContent
    
    var rowsCount: Int { get }
    func row(at index: Int) -> ModelRow
    
}

extension FormViewModelProtocol {

    typealias ModelRow = Row<RowIdentifier, RowContent>
    
}

struct FormViewModel<RowIdentifier : Hashable, RowContent> : FormViewModelProtocol {
    
    private var rows: [Row<RowIdentifier, RowContent>] = []
    
    init(rows: [FormViewModel.ModelRow]) {
        self.rows = rows
    }
    
    func row(at index: Int) -> Row<RowIdentifier, RowContent> {
        return rows[index]
    }
    
    var rowsCount: Int {
        return rows.count
    }
    
}

protocol FormViewModelGenerator {
    
    associatedtype Model : FormModel
    associatedtype RowContent
    
    func generate(from model: Model) -> FormViewModel<Model.Key, RowContent>
    
}

struct FormViewModelBasicGenerator<Identifier : Hashable, FormModelValueType : FormModelValue, RowContent> {
    
    let generateRowContent: (FormModelValueType) -> RowContent
    
    func generateViewModel<Model : DictionaryBasedFormModel & OrderedKeysFormModel>(from model: Model) -> FormViewModel<Identifier, RowContent> where Model.Key == Identifier, Model.Value == FormModelValueType {
        let rows = zip(model.orderedKeys, model.orderedValues).map({ Row<Identifier, RowContent>(identifier: $0.0, content: generateRowContent($0.1)) })
        return FormViewModel(rows: rows)
    }
    
}

enum MFP {
    
    enum RowContent {
        case textField(TextFieldRowModel)
        case selection(SelectionRowModel)
    }
    
    struct TextFieldRowModel {
        let text: String?
        let label: String?
        let keyboardType: UIKeyboardType
        let validationState: ValidationResult
    }
    
    struct SelectionRowModel {
        let label: String?
        let selection: [String]
        let placeholder: String?
        let selectedIndex: Int?
    }
    
}

struct AFormViewModelGenerator : FormViewModelGenerator {
    
    typealias Model = AModel
    typealias RowContent = MFP.RowContent
    
    func generate(from model: AModel) -> FormViewModel<AModelKeys, MFP.RowContent> {
        let rows = generateRows(from: model)
        return FormViewModel(rows: rows)
    }
    
    func generateRows(from model: AModel) -> [Row<AModelKeys, MFP.RowContent>] {
        let rows: [Row<AModelKeys, MFP.RowContent>] = zip(model.orderedKeys, model.orderedValues).map { (key, value) in
            switch value {
            case .textInput(let string, of: let inputType):
                let tfrm = MFP.TextFieldRowModel.init(text: string,
                                                      label: label(for: key),
                                                      keyboardType: keyboardType(for: inputType),
                                                      validationState: model.validate(key))
                return Row(identifier: key, content: .textField(tfrm))
            case .selection(let selection, selected: let selected, placeholder: let placeholder):
                let selectionRowModel = MFP.SelectionRowModel.init(label: label(for: key),
                                                                   selection: selection,
                                                                   placeholder: placeholder,
                                                                   selectedIndex: selected)
                return Row(identifier: key, content: .selection(selectionRowModel))
            }
        }
        return rows
    }
    
    func keyboardType(for inputType: BasicModelValue.InputType) -> UIKeyboardType {
        switch inputType {
        case .string:
            return UIKeyboardType.default
        case .integer:
            return UIKeyboardType.numberPad
        case .floating:
            return UIKeyboardType.decimalPad
        }
    }
    
    func label(for key: Model.Key) -> String? {
        switch key {
        case .name:
            return "Name"
        case .age:
            return "Age"
        case .gender:
            return "Gender"
        }
    }
    
}

let mfpGenerator = AFormViewModelGenerator()
let viewModel = mfpGenerator.generate(from: model)
print(viewModel.row(at: 2))
try! model.set(1, for: .gender)
try! model.set("15a", for: .age)
let nextViewModel = mfpGenerator.generate(from: model)
print(nextViewModel.row(at: 1))

class Interactor {
    
    let output: Presenter
    init(output: Presenter) {
        self.output = output
    }
    
    var model = AModel()
    
    func didSetValue(_ value: Any?, at key: AModelKeys) {
        do {
            try model.set(value, for: key)
            output.updateViewModel(with: model)
        } catch {
            print(error)
        }
    }
    
}

class Presenter {
    
    let generator = AFormViewModelGenerator()
    weak var interactor: Interactor?
    
    func updateViewModel(with model: AModel) {
        dump(generator.generate(from: model))
    }
    
    func didSetValue(_ value: Any?, at key: AModelKeys) {
        interactor?.didSetValue(value, at: key)
    }
    
}

let pr = Presenter()
let inter = Interactor(output: pr)
pr.interactor = inter

pr.didSetValue(1, at: .gender)
