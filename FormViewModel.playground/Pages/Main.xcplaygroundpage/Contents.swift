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

extension FormModel {
    
    func specificValue<T>(for key: Key) -> T? {
        if let value = value(for: key) {
            return value as? T
        }
        return nil
    }
    
}

protocol OrderedKeysFormModel : FormModel {
    
    var orderedKeys: [Key] { get }
    
}

protocol ValidatingValuesFormModel : FormModel {
    
    func validate(valueAt key: Key) -> ValidationResult
    
}

extension ValidatingValuesFormModel {
    
    func validateWithDescription(valueAt key: Key) -> ValidationResult {
        switch validate(valueAt: key) {
        case .valid:
            return .valid
        case .notValid(reasons: let reasons):
            var rs = reasons
            if var last = rs.popLast() {
                last.append(" (\(String(describing: key).capitalized))")
                rs.append(last)
            }
            return .notValid(reasons: rs)
        }
    }
    
}

extension ValidatingValuesFormModel where Self : OrderedKeysFormModel {
    
    func validateModelByCombining() -> ValidationResult {
        return orderedKeys.map(self.validateWithDescription(valueAt:)).reduce(.valid, ValidationResult.combine)
    }
    
}

protocol ValidatingModelFormModel : FormModel {
    
    func validateModel() -> ValidationResult
    
}

protocol DictionaryBasedFormModel : FormModel {
    
    var fields: [Key : Value] { get set }
    
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

protocol OutputtableFormModel : FormModel {
    
    associatedtype Output
    
    func output() throws -> Output
    
}

extension OutputtableFormModel where Self : ValidatingModelFormModel {
    
    func validOutput() throws -> Output {
        let validationResult = self.validateModel()
        if let error = ValidationResultError.init(validationResult) {
            throw error
        }
        return try output()
    }
    
}

struct A {
    let name: String?
    let age: Int?
    let genderID: Int?
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

struct AModel : OrderedKeysFormModel, ValidatingValuesFormModel, ValidatingModelFormModel, DictionaryBasedFormModel {
    
    typealias Key = AModelKeys
    typealias Value = BasicModelValue
    
    var fields: [AModelKeys : BasicModelValue] = [
        .name: .textInput(nil, of: .string),
        .age: .textInput(nil, of: .integer),
        .gender: .selection([Gender.male.rawValue, Gender.female.rawValue], selected: nil, placeholder: "Select Gender"),
    ]
    
    let orderedKeys: [AModelKeys] = [.name, .age, .gender]
    
    func validate(valueAt key: AModelKeys) -> ValidationResult {
        let value = self.value(for: key)
        switch key {
        case .name:
            return val(value, with: Validators.stringLength0_30) ?? .valid
        case .age:
            return transformingValidate(value, with: Validators.stringToInt)?
                .validate(with: Validators.age0_99) ?? .valid
        case .gender:
            return .valid
        }
    }
    
    func validateModel() -> ValidationResult {
        return validateModelByCombining()
    }
    
}

extension AModel {
    
    enum Validators {
        
        static func stringLength0_30(_ string: String) -> ValidationResult {
            return (0 ... 10) ~= string.characters.count ? .valid : .notValid(reasons: ["Invalid string length"])
        }
        
        static let stringToInt: TransformingValidator<String, Int> = { string in
            if let int = Int(string) {
                return .valid(int)
            } else {
                return .notValid(reasons: ["Cannot convert String to Int"])
            }
        }
        
        static func age0_99(_ age: Int) -> ValidationResult {
            return (0 ... 99) ~= age ? .valid : .notValid(reasons: ["Age should be from 0 to 99"])
        }
        
    }
    
}

extension String : Swift.Error { }

extension AModel : OutputtableFormModel {
    
    typealias Output = A
    
    func output() throws -> A {
        return A.init(name: specificValue(for: .name),
                      age: specificValue(for: .age).flatMap({ Int($0) }),
                      genderID: specificValue(for: .gender))
    }
    
}

var model = AModel()

try! model.set("Alba", for: .name)
print(model.orderedValues)
try! model.set("15a", for: .age)
model.validateModel()
model.validateWithDescription(valueAt: .age)

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
    
    init(rows: [Row<RowIdentifier, RowContent>]) {
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
    
    var needsValidation: Bool
    
    init(needsValidation: Bool = true) {
        self.needsValidation = needsValidation
    }
    
    typealias Model = AModel
    typealias RowContent = MFP.RowContent
    
    func generate(from model: AModel) -> FormViewModel<AModelKeys, MFP.RowContent> {
        let rows = generateRows(from: model)
        return FormViewModel(rows: rows)
    }
    
    func validateValue(for key: Model.Key) -> ValidationResult {
        return needsValidation ? model.validateWithDescription(valueAt: key) : .valid
    }
    
    func generateRows(from model: AModel) -> [Row<AModelKeys, MFP.RowContent>] {
        let rows: [Row<AModelKeys, MFP.RowContent>] = zip(model.orderedKeys, model.orderedValues).map { (key, value) in
            switch value {
            case .textInput(let string, of: let inputType):
                let tfrm = MFP.TextFieldRowModel.init(text: string,
                                                      label: label(for: key),
                                                      keyboardType: keyboardType(for: inputType),
                                                      validationState: validateValue(for: key))
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
        output.updateViewModel(with: model)
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
    let view = View()
    
    func updateViewModel(with model: AModel) {
        let viewModel = generator.generate(from: model)
        view.viewModel = viewModel
    }
    
    func didSetValue(_ value: Any?, at key: AModelKeys) {
        interactor?.didSetValue(value, at: key)
    }
    
}

class View {
    
    var viewModel: FormViewModel<AModelKeys, MFP.RowContent>! {
        didSet {
            dump(viewModel)
            print(Date())
        }
    }
    weak var output: Presenter!
    
    func somehowSet(_ value: Any?, at key: AModelKeys) {
        output.didSetValue(value, at: key)
    }
    
}

let pr = Presenter()
let inter = Interactor(output: pr)
pr.interactor = inter

let view = pr.view
view.output = pr
view.somehowSet("15", at: .age)
view.somehowSet(1, at: .gender)
view.somehowSet("Alba Esso", at: .name)
view.somehowSet("My name is Nathan Drake", at: .name)
view.somehowSet("121", at: .age)
inter.model.validateModel()

do {
    let output = try inter.model.validOutput()
    print(output)
} catch {
    print(error)
}
