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

#ifndef RUBYTAB_H
#define RUBYTAB_H

#include <QLineEdit>
#include <QMenu>
#include <QPlainTextEdit>
#include <QTextEdit>
#include "nextpnr.h"

NEXTPNR_NAMESPACE_BEGIN

class RubyConsole : public QTextEdit
{
    Q_OBJECT

  public:
    explicit RubyConsole(QWidget *parent = 0);
    void displayString(QString text);
    void moveCursorToEnd();

  public Q_SLOTS:
    void execute_ruby(std::string filename);
    void executeCommand(const std::string &command);

  private:
    static const QColor NORMAL_COLOR;
    static const QColor ERROR_COLOR;
    static const QColor OUTPUT_COLOR;
};

class RubyTab : public QWidget
{
    Q_OBJECT

  public:
    explicit RubyTab(QWidget *parent = 0);
    ~RubyTab();

  private Q_SLOTS:
    void showContextMenu(const QPoint &pt);
    void editLineReturnPressed();
  public Q_SLOTS:
    void newContext(Context *ctx);
    void info(std::string str);
    void clearBuffer();
    void execute_ruby(std::string filename);

  private:
    RubyConsole *console;
    QLineEdit *lineEdit;
    QMenu *contextMenu;
    bool initialized;
    QString prompt;

    static const QString PROMPT;
    static const QString MULTILINE_PROMPT;
};

NEXTPNR_NAMESPACE_END

#endif // RUBYTAB_H
