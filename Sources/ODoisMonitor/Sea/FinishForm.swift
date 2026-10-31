import AppKit

/// Confirmação antes de gravar no Dashboard: horas (editáveis), data, tipo de atividade
/// e comentário. Nada é gravado sem passar por aqui.
@MainActor
struct FinishForm {
    struct Result {
        let hours: Double
        let date: Date
        let activityType: Int
        let comment: String
    }

    let timer: TaskTimer
    let types: [SeaActivityType]
    let preferred: Int?

    /// Horas do cronômetro com duas casas (o Dashboard aceita decimais).
    private var suggestedHours: Double {
        (timer.elapsed() / 3600 * 100).rounded() / 100
    }

    func run() -> Result? {
        let hoursField = NSTextField(string: Self.decimal(max(suggestedHours, 0.01)))
        hoursField.placeholderString = "1,5"

        let datePicker = NSDatePicker()
        datePicker.datePickerElements = .yearMonthDay
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.dateValue = timer.startedAt
        datePicker.maxDate = Date()

        let typePopup = NSPopUpButton()
        typePopup.addItems(withTitles: types.map(\.label))
        let defaultIndex = types.firstIndex { $0.id == preferred }
            ?? types.firstIndex { $0.label == "Desenvolvimento" } ?? 0
        typePopup.selectItem(at: defaultIndex)

        let commentField = NSTextField(string: "")
        commentField.placeholderString = "O que foi feito (opcional)"

        let grid = NSGridView(views: [
            [label("Horas"), hoursField],
            [label("Data"), datePicker],
            [label("Atividade"), typePopup],
            [label("Comentário"), commentField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 240
        grid.frame = NSRect(x: 0, y: 0, width: 330, height: 120)

        let alert = NSAlert()
        alert.messageText = "Registrar horas em \(timer.task.title)?"
        alert.informativeText = "\(timer.task.projectName) · cronômetro em \(SeaStore.clock(timer.elapsed())). "
            + "A entrada vai para a sua folha de horas da semana."
        alert.accessoryView = grid
        alert.addButton(withTitle: "Registrar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = commentField

        while alert.runModal() == .alertFirstButtonReturn {
            let text = hoursField.stringValue.replacingOccurrences(of: ",", with: ".")
            guard let hours = Double(text), hours > 0, hours <= 24 else {
                alert.informativeText = "Informe as horas como número entre 0 e 24 (ex.: 1,5)."
                continue
            }
            return Result(
                hours: (hours * 100).rounded() / 100,
                date: datePicker.dateValue,
                activityType: types[max(typePopup.indexOfSelectedItem, 0)].id,
                comment: commentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return nil
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private static func decimal(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}
