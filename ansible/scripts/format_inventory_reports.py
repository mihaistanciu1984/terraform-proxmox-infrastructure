#!/usr/bin/env python3

import argparse
import pathlib
import re
import sys


REPORT_WIDTH = 88
FORMAT_MARKER = "Report format   : Junior-friendly TXT"
SEPARATOR_PATTERN = re.compile(r"^={20,}$")
SUBHEADING_PATTERN = re.compile(r"^---\s*(.*?)\s*---$")


def make_title(title: str, number: int | None = None) -> list[str]:
    if number is not None:
        title = f"{number:02d}. {title}"

    border = "=" * REPORT_WIDTH

    return [
        border,
        title.center(REPORT_WIDTH),
        border,
    ]


def find_headings(lines: list[str]) -> list[str]:
    headings: list[str] = []
    index = 0

    while index < len(lines) - 2:
        if (
            SEPARATOR_PATTERN.match(lines[index].strip())
            and lines[index + 1].strip()
            and SEPARATOR_PATTERN.match(lines[index + 2].strip())
        ):
            headings.append(lines[index + 1].strip())
            index += 3
            continue

        index += 1

    return headings


def remove_excess_blank_lines(lines: list[str]) -> list[str]:
    cleaned: list[str] = []
    previous_was_blank = False

    for line in lines:
        is_blank = not line.strip()

        if is_blank and previous_was_blank:
            continue

        cleaned.append(line.rstrip())
        previous_was_blank = is_blank

    while cleaned and not cleaned[-1].strip():
        cleaned.pop()

    return cleaned


def format_report(content: str) -> str:
    if FORMAT_MARKER in content:
        return content

    raw_lines = content.replace("\r\n", "\n").splitlines()
    headings = find_headings(raw_lines)

    if not headings:
        return content

    main_title = headings[0]

    section_titles = [
        heading
        for heading in headings[1:]
        if heading.upper() != "END OF REPORT"
    ]

    formatted: list[str] = []
    heading_number = 0
    index = 0
    main_title_written = False

    while index < len(raw_lines):
        current_line = raw_lines[index].rstrip()

        if (
            index + 2 < len(raw_lines)
            and SEPARATOR_PATTERN.match(current_line.strip())
            and raw_lines[index + 1].strip()
            and SEPARATOR_PATTERN.match(raw_lines[index + 2].strip())
        ):
            title = raw_lines[index + 1].strip()

            if not main_title_written:
                formatted.extend(make_title(main_title))
                formatted.append(FORMAT_MARKER)
                formatted.append("")

                if section_titles:
                    formatted.append("CONTENTS")
                    formatted.append("-" * REPORT_WIDTH)

                    for section_number, section_title in enumerate(
                        section_titles,
                        start=1,
                    ):
                        formatted.append(
                            f"  {section_number:02d}. {section_title}"
                        )

                    formatted.append("")

                main_title_written = True

            elif title.upper() == "END OF REPORT":
                formatted.extend(make_title("END OF REPORT"))

            else:
                heading_number += 1
                formatted.extend(make_title(title, heading_number))

            index += 3
            continue

        subheading_match = SUBHEADING_PATTERN.match(current_line.strip())

        if subheading_match:
            subheading = subheading_match.group(1)

            formatted.append("")
            formatted.append(f"  {subheading}")
            formatted.append("  " + "-" * (REPORT_WIDTH - 2))
            index += 1
            continue

        formatted.append(current_line)
        index += 1

    formatted = remove_excess_blank_lines(formatted)

    return "\n".join(formatted) + "\n"


def format_file(report_file: pathlib.Path) -> bool:
    try:
        original_content = report_file.read_text(
            encoding="utf-8",
            errors="replace",
        )

        formatted_content = format_report(original_content)

        if formatted_content == original_content:
            return False

        report_file.write_text(
            formatted_content,
            encoding="utf-8",
        )

        return True

    except OSError as error:
        print(
            f"[ERROR] Could not format {report_file}: {error}",
            file=sys.stderr,
        )
        return False


def collect_report_files(target: pathlib.Path) -> list[pathlib.Path]:
    if target.is_file():
        return [target] if target.suffix.lower() == ".txt" else []

    if target.is_dir():
        return sorted(target.glob("*.txt"))

    return []


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Format Proxmox inventory TXT reports.",
    )

    parser.add_argument(
        "target",
        type=pathlib.Path,
        help="TXT report or directory containing TXT reports.",
    )

    arguments = parser.parse_args()
    report_files = collect_report_files(arguments.target)

    if not report_files:
        print(f"[INFO] No TXT reports found in {arguments.target}")
        return 0

    formatted_count = 0

    for report_file in report_files:
        if format_file(report_file):
            formatted_count += 1
            print(f"[OK] Formatted: {report_file.name}")

    print(
        f"[INFO] Formatted {formatted_count} new report(s); "
        f"checked {len(report_files)} report(s)."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())