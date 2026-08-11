import Foundation

public enum IssueSeverity: String, Sendable, Hashable {
    case warning
    case error
}

public struct CompilationIssue: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let severity: IssueSeverity
    public let line: Int
    public let message: String
    public let source: String

    public init(
        severity: IssueSeverity,
        line: Int,
        message: String,
        source: String,
        id: UUID = UUID()
    ) {
        self.id = id
        self.severity = severity
        self.line = line
        self.message = message
        self.source = source
    }
}

public struct CompilationOptions: Sendable, Hashable {
    public var convertUnsupportedLinesToComments: Bool

    public init(convertUnsupportedLinesToComments: Bool = true) {
        self.convertUnsupportedLinesToComments = convertUnsupportedLinesToComments
    }
}

public struct CompilationResult: Sendable {
    public let source: String
    public let logicalLines: [LogicalLine]
    public let steps: [CompiledStep]
    public let issues: [CompilationIssue]
    public let xml: String
    public let supportedStepCount: Int
    public let commentFallbackCount: Int
    public let preservedStepCount: Int

    public var errorCount: Int {
        issues.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    public var canCopyToFileMaker: Bool {
        !steps.isEmpty && errorCount == 0
    }
}

public struct LogicalLine: Sendable, Hashable {
    public let lineNumber: Int
    public let text: String

    public init(lineNumber: Int, text: String) {
        self.lineNumber = lineNumber
        self.text = text
    }
}

public enum CompiledStep: Sendable, Hashable {
    case comment(text: String, isFallback: Bool)
    case setVariable(name: String, value: String, repetition: String?)
    case setField(table: String, field: String, value: String)
    case setFieldByName(target: String, value: String)
    case ifStep(calculation: String)
    case elseIf(calculation: String)
    case elseStep
    case endIf
    case loop(flush: LoopFlushMode)
    case exitLoopIf(calculation: String)
    case endLoop
    case performScript(name: String, parameter: String?)
    case performScriptOnServer(name: String, parameter: String?, waitForCompletion: Bool)
    case goToLayout(name: String)
    case goToRecord(destination: RecordPageDestination, exitAfterLast: Bool)
    case showCustomDialog(title: String?, message: String, buttons: [DialogButton])
    case newWindow(options: NewWindowOptions)
    case selectWindow(target: WindowTarget)
    case closeWindow(target: WindowTarget)
    case recordDialogStep(id: Int, name: String, noInteract: Bool)
    case enterFindMode(pause: Bool)
    case performFind(restore: Bool)
    case exitScript(result: String?)
    case toggle(id: Int, name: String, enabled: Bool)
    case enumOption(id: Int, name: String, element: String, value: String)
    case showHide(id: Int, name: String, value: String, lock: Bool, includeEditRecordToolbar: Bool?)
    case setZoomLevel(value: String, calculation: String?, lock: Bool)
    case moveResizeWindow(target: WindowTarget, height: String?, width: String?, distanceFromTop: String?, distanceFromLeft: String?)
    case setWindowTitle(target: WindowTarget, newName: String?)
    case findMatchingRecords(mode: String, table: String?, field: String?)
    case performQuickFind(calculation: String)
    case sortRecordsByField(mode: String, table: String?, field: String?)
    case constrainFoundSet(findWithoutIndexes: Bool)
    case omitMultipleRecords(withDialog: Bool, calculation: String?)
    case sortRecords(withDialog: Bool, sortList: SortRecordList?)
    case importRecords(options: ImportRecordsOptions)
    case exportRecords(options: ExportRecordsOptions)
    case saveRecordsAsExcel(options: SaveRecordsAsExcelOptions)
    case sendMail(options: SendMailOptions)
    case noOption(id: Int, name: String)
    case exportFieldContents(table: String, field: String, path: String, createDirectories: Bool)
    case insertFile(table: String, field: String, path: String)
    case refreshObject(objectName: String, repetition: String)
    case preservedXML(token: String, name: String, xml: String)

    public var isFallbackComment: Bool {
        if case .comment(_, let isFallback) = self {
            return isFallback
        }
        return false
    }

    public var isPreservedStep: Bool {
        if case .preservedXML = self {
            return true
        }
        return false
    }
}

public enum LoopFlushMode: String, Sendable, Hashable, CaseIterable {
    case always = "Always"
    case minimum = "Minimum"
    case never = "Never"
}

public enum RecordPageDestination: Sendable, Hashable {
    case first
    case last
    case previous
    case next
    case byCalculation(String)
}

public struct SortRecordCriterion: Sendable, Hashable {
    public let table: String
    public let field: String
    public let order: SortOrder

    public init(table: String, field: String, order: SortOrder) {
        self.table = table
        self.field = field
        self.order = order
    }
}

public struct SortRecordList: Sendable, Hashable {
    public let blanksLast: Bool
    public let keepRecordsSorted: Bool
    public let criteria: [SortRecordCriterion]

    public init(blanksLast: Bool, keepRecordsSorted: Bool, criteria: [SortRecordCriterion]) {
        self.blanksLast = blanksLast
        self.keepRecordsSorted = keepRecordsSorted
        self.criteria = criteria
    }
}

public enum SortOrder: String, Sendable, Hashable {
    case ascending = "Ascending"
    case descending = "Descending"
}

public struct ImportRecordsOptions: Sendable, Hashable {
    public let withDialog: Bool
    public let path: String

    public init(withDialog: Bool, path: String) {
        self.withDialog = withDialog
        self.path = path
    }
}

public struct ExportRecordsOptions: Sendable, Hashable {
    public let withDialog: Bool
    public let createDirectories: Bool
    public let path: String
    public let characterSet: String
    public let useFieldNames: Bool
    public let fields: [ExportRecordField]

    public init(withDialog: Bool, createDirectories: Bool, path: String, characterSet: String, useFieldNames: Bool, fields: [ExportRecordField]) {
        self.withDialog = withDialog
        self.createDirectories = createDirectories
        self.path = path
        self.characterSet = characterSet
        self.useFieldNames = useFieldNames
        self.fields = fields
    }
}

public struct SaveRecordsAsExcelOptions: Sendable, Hashable {
    public let withDialog: Bool
    public let createDirectories: Bool
    public let path: String
    public let saveType: String
    public let useFieldNames: Bool

    public init(withDialog: Bool, createDirectories: Bool, path: String, saveType: String, useFieldNames: Bool) {
        self.withDialog = withDialog
        self.createDirectories = createDirectories
        self.path = path
        self.saveType = saveType
        self.useFieldNames = useFieldNames
    }
}

public struct ExportRecordField: Sendable, Hashable {
    public let table: String
    public let field: String

    public init(table: String, field: String) {
        self.table = table
        self.field = field
    }
}

public struct SendMailOptions: Sendable, Hashable {
    public let withDialog: Bool
    public let attachmentPath: String

    public init(withDialog: Bool, attachmentPath: String) {
        self.withDialog = withDialog
        self.attachmentPath = attachmentPath
    }
}

public struct DialogButton: Sendable, Hashable {
    public let calculation: String
    public let commitsRecord: Bool

    public init(calculation: String, commitsRecord: Bool) {
        self.calculation = calculation
        self.commitsRecord = commitsRecord
    }
}

public enum WindowTarget: Sendable, Hashable {
    case current
    case byName(calculation: String, currentFileOnly: Bool)
}

public struct NewWindowOptions: Sendable, Hashable {
    public let style: String
    public let nameCalculation: String
    public let layoutName: String
    public let close: Bool
    public let minimize: Bool
    public let maximize: Bool
    public let resize: Bool
    public let menuBar: Bool
    public let dimParentWindow: Bool
    public let toolbars: Bool

    public init(
        style: String,
        nameCalculation: String,
        layoutName: String,
        close: Bool,
        minimize: Bool,
        maximize: Bool,
        resize: Bool,
        menuBar: Bool,
        dimParentWindow: Bool,
        toolbars: Bool
    ) {
        self.style = style
        self.nameCalculation = nameCalculation
        self.layoutName = layoutName
        self.close = close
        self.minimize = minimize
        self.maximize = maximize
        self.resize = resize
        self.menuBar = menuBar
        self.dimParentWindow = dimParentWindow
        self.toolbars = toolbars
    }
}

public struct PreservedFileMakerStep: Sendable, Hashable {
    public let token: String
    public let name: String
    public let id: Int?
    public let xml: String

    public init(token: String, name: String, id: Int?, xml: String) {
        self.token = token
        self.name = name
        self.id = id
        self.xml = xml
    }
}

public struct DecompilationResult: Sendable {
    public let sourceXML: String
    public let text: String
    public let stepCount: Int
    public let unsupportedStepCount: Int
    public let scriptNames: [String]
    public let warnings: [String]
    public let preservedSteps: [String: PreservedFileMakerStep]

    public init(
        sourceXML: String,
        text: String,
        stepCount: Int,
        unsupportedStepCount: Int,
        scriptNames: [String],
        warnings: [String],
        preservedSteps: [String: PreservedFileMakerStep] = [:]
    ) {
        self.sourceXML = sourceXML
        self.text = text
        self.stepCount = stepCount
        self.unsupportedStepCount = unsupportedStepCount
        self.scriptNames = scriptNames
        self.warnings = warnings
        self.preservedSteps = preservedSteps
    }

    public var isSuccessful: Bool {
        stepCount > 0 && !text.isEmpty
    }
}
