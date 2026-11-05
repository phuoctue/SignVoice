# Calibration giới hạn cho cặp model mới, 22/10/2026

Đăng ký trước lượt chạy. Chỉ chạy offline, không train, không sửa app/service/public/notebook. Cặp mới là encoder/prototype đã kiểm checksum đi cùng TCN `latest137` (AD), cùng normalizer; không trộn encoder mới với prototype cũ.

## Cấu hình cố định

| Tên | Trọng số TCN | Nhiệt độ TCN | Nhiệt độ embedding |
|---|---:|---:|---:|
| anchor | 0,50 | 1,00 | 0,06 |
| tcn25 | 0,25 | 1,00 | 0,06 |
| tcn75 | 0,75 | 1,00 | 0,06 |
| tcn_sharper | 0,50 | 0,75 | 0,06 |
| embedding_sharper | 0,50 | 1,00 | 0,04 |
| embedding_softer | 0,50 | 1,00 | 0,09 |

Mỗi biến thể chỉ đổi một tham số so với anchor. Không thử phối hợp những tham số đẹp sau khi xem kết quả. Đây là sàng lọc hữu hạn, không phải tìm tối ưu toàn cục hay xác suất đã được kiểm định. Nhiệt độ có thể làm thay đổi mức tự tin và nhận/từ chối, dù giữ nguyên ngưỡng.

Giữ score/min_dynamic_score 0,60, margin/min_dynamic_margin 0,20, dwell 0,30, smoothing, buffer, pair/motion gates, slot matching và lịch dự đoán app 0,25s/gap 0,60s. Trọng số embedding khai báo bằng 1−trọng số TCN. Background được giữ theo xác suất TCN đã temperature-scale như hàm fusion đang dùng; không bỏ veto hay chốt sớm.

## Dữ liệu và kiểm tra

Tái dùng bộ cache nguồn đã xác minh, đúng giao thức so checkpoint: 95 calibration và 109 epoch VAL từ 297 clip cũ; loại 93 audit của giao thức mới trước I/O feature/source. Kiểm TRAIN overlap theo ID/content/source hash. Không dùng các clip TRAIN rau trước đây. Không mở thêm audit. Audit đã bị lộ ở giao thức cũ không thể coi là TEST mới.

Chọn cấu hình trên 94 calibration sau khi tách 1 chào KhangCN chưa xác minh. Báo cả 95 và 94, theo từ và nguồn. Không dùng 109 epoch VAL hoặc webcam để chọn. Bộ calibration này đã xem nhiều lần; mọi số chỉ là dữ liệu phát triển. Những từ thiếu mẫu phải ghi chưa đo.

Chỉ gọi là ứng viên phát triển nếu so với anchor trên 94 clip: macro recall tăng, số đúng không giảm, accepted precision >= max(0,95, precision anchor), số clip sai/sự kiện sai/trùng không tăng; các từ ưu tiên có mẫu không mất số đúng. Từ ưu tiên thiếu mẫu phải báo riêng, không giả định đạt. Trong các ứng viên hợp lệ, chọn theo macro recall, precision, ít sự kiện sai, gần anchor nhất rồi tên cố định. Nếu không có, giữ anchor với lý do `no_supported_development_improvement`. Không coi kết quả không đạt là phương pháp vô ích.

Sau khi ghi lựa chọn ra file, chỉ chạy app, anchor và ứng viên (nếu khác anchor) trên 109 epoch VAL. Báo đối chiếu và CI/McNemar mô tả; cảnh báo nhóm gần như từng video, nhiều từ chỉ một clip, CI suy biến và nhiều phép so sánh. Không dùng p-value sau quét làm chứng nhận thắng. Đọc so với app riêng: đạt so với cặp mới chưa có nghĩa tốt hơn app hiện tại.

Sau bước chọn, replay bản ghi webcam có PNG ngày 22/10, chỉ app/anchor/ứng viên, đúng batch/generation/allow_prediction. Đây là probe phát triển đã xem, không dùng để chọn hoặc báo accuracy độc lập. Sự kiện khác có thể đúng/sai chưa được chú giải thời gian độc lập.

## Độ tin cậy của lượt chạy

Smoke chọn tối đa một clip đúng/không chốt/sai mỗi role theo kết quả app cũ; không dùng số smoke làm bằng chứng. FULL chỉ chạy khi smoke cùng băm mã/cấu hình/asset/cohort gốc đã hoàn thành. Không sửa mã giữa hai lượt.

Mỗi clip: app phải khớp kết quả đóng băng; anchor phải khớp điểm fusion mới cố định của lượt checkpoint trước. Lặp app và anchor ở cuối để kiểm mọi vector scores/output tại mọi input và toàn bộ event. Memo chỉ cache lời gọi neural theo byte tensor, không cache quyết định. Ghi journal từng clip, resume chỉ khi hợp đồng không đổi. Hợp đồng chứa checksum code/dependencies, asset/split, toàn bộ ID vai trò, thông số và webcam. Báo và dừng khi thiếu clip, nguồn thay đổi, gate khác hoặc sai đối chứng.

Đầu ra có bảng đủ 181 từ, gained/lost, theo nguồn và missing coverage. Không tự triển khai kể cả có ứng viên, vì chưa có nền thật và webcam độc lập theo người/phiên. Nếu chỉ đổi fusion vẫn không giúp hoặc cả hai nhánh xếp sai, bước tiếp là dữ liệu webcam TRAIN/cửa sổ live/nền thật, không tiếp tục quét vô hạn hay giảm dwell theo bốn từ.
