/*
 *  nextpnr -- Next Generation Place and Route
 *
 *  Copyright (C) 2018  Miodrag Milanovic <micko@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#include "rubytab.h"
#include <QGridLayout>
#include "rubybindings.h"

#include <mruby.h>
#include <mruby/compile.h>
#include <mruby/string.h>

NEXTPNR_NAMESPACE_BEGIN

// -------------------------------------------------------
// RubyConsole
// -------------------------------------------------------

const QColor RubyConsole::NORMAL_COLOR = QColor::fromRgbF(0, 0, 0);
const QColor RubyConsole::ERROR_COLOR = QColor::fromRgbF(1.0, 0, 0);
const QColor RubyConsole::OUTPUT_COLOR = QColor::fromRgbF(0, 0, 1.0);

RubyConsole::RubyConsole(QWidget *parent) : QTextEdit(parent) {}

void RubyConsole::displayString(QString text)
{
    QTextCursor cursor = textCursor();
    cursor.movePosition(QTextCursor::End);
    setTextColor(NORMAL_COLOR);
    cursor.insertText(text);
    cursor.movePosition(QTextCursor::EndOfLine);
    moveCursorToEnd();
}

void RubyConsole::moveCursorToEnd()
{
    QTextCursor cursor = textCursor();
    cursor.movePosition(QTextCursor::End);
    setTextCursor(cursor);
}

void RubyConsole::executeCommand(const std::string &command)
{
    mrb_state *mrb = get_ruby_state();
    if (!mrb) return;

    mrb_value result = mrb_load_string(mrb, command.c_str());

    if (mrb->exc) {
        mrb_value exc = mrb_obj_value(mrb->exc);
        mrb_value msg = mrb_funcall(mrb, exc, "inspect", 0);
        setTextColor(ERROR_COLOR);
        append(mrb_str_to_cstr(mrb, msg));
        mrb->exc = 0;
    } else if (!mrb_nil_p(result)) {
        mrb_value str = mrb_funcall(mrb, result, "inspect", 0);
        setTextColor(OUTPUT_COLOR);
        append(mrb_str_to_cstr(mrb, str));
    }

    setTextColor(NORMAL_COLOR);
    append("");
    moveCursorToEnd();
}

void RubyConsole::execute_ruby(std::string filename)
{
    mrb_state *mrb = get_ruby_state();
    if (!mrb) return;

    FILE *fp = fopen(filename.c_str(), "r");
    if (!fp) {
        setTextColor(ERROR_COLOR);
        append(QString("File not found: %1").arg(filename.c_str()));
        setTextColor(NORMAL_COLOR);
        return;
    }

    mrbc_context *cxt = mrbc_context_new(mrb);
    mrbc_filename(mrb, cxt, filename.c_str());
    mrb_load_file_cxt(mrb, fp, cxt);
    mrbc_context_free(mrb, cxt);
    fclose(fp);

    if (mrb->exc) {
        mrb_value exc = mrb_obj_value(mrb->exc);
        mrb_value msg = mrb_funcall(mrb, exc, "inspect", 0);
        setTextColor(ERROR_COLOR);
        append(mrb_str_to_cstr(mrb, msg));
        mrb->exc = 0;
    }

    setTextColor(NORMAL_COLOR);
    moveCursorToEnd();
}

// -------------------------------------------------------
// RubyTab
// -------------------------------------------------------

const QString RubyTab::PROMPT = "rb> ";
const QString RubyTab::MULTILINE_PROMPT = "... ";

RubyTab::RubyTab(QWidget *parent) : QWidget(parent), initialized(false)
{
    QFont f("unexistent");
    f.setStyleHint(QFont::Monospace);

    console = new RubyConsole();
    console->setMinimumHeight(100);
    console->setReadOnly(true);
    console->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    console->setFont(f);

    console->setContextMenuPolicy(Qt::CustomContextMenu);
    QAction *clearAction = new QAction("Clear &buffer", this);
    clearAction->setStatusTip("Clears display buffer");
    connect(clearAction, &QAction::triggered, this, &RubyTab::clearBuffer);
    contextMenu = console->createStandardContextMenu();
    contextMenu->addSeparator();
    contextMenu->addAction(clearAction);
    connect(console, &RubyConsole::customContextMenuRequested, this, &RubyTab::showContextMenu);

    lineEdit = new QLineEdit();
    lineEdit->setMinimumHeight(30);
    lineEdit->setMaximumHeight(30);
    lineEdit->setFont(f);
    lineEdit->setPlaceholderText(RubyTab::PROMPT);
    connect(lineEdit, &QLineEdit::returnPressed, this, &RubyTab::editLineReturnPressed);

    QGridLayout *mainLayout = new QGridLayout();
    mainLayout->addWidget(console, 0, 0);
    mainLayout->addWidget(lineEdit, 1, 0);
    setLayout(mainLayout);

    prompt = RubyTab::PROMPT;
}

RubyTab::~RubyTab()
{
    if (initialized) {
        deinit_ruby();
    }
}

void RubyTab::editLineReturnPressed()
{
    QString text = lineEdit->text();
    lineEdit->clear();

    console->displayString(prompt + text + "\n");
    console->executeCommand(text.toStdString());
}

void RubyTab::newContext(Context *ctx)
{
    if (initialized) {
        deinit_ruby();
    }
    console->clear();

    init_ruby("nextpnr");
    ruby_export_global("ctx", ctx);

    initialized = true;

    console->displayString(QString("mruby interactive console\n"));
}

void RubyTab::showContextMenu(const QPoint &pt) { contextMenu->exec(mapToGlobal(pt)); }

void RubyTab::clearBuffer() { console->clear(); }

void RubyTab::info(std::string str) { console->displayString(str.c_str()); }

void RubyTab::execute_ruby(std::string filename) { console->execute_ruby(filename); }

NEXTPNR_NAMESPACE_END
