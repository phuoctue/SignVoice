# Bản ghi camera có PNG, 22/10/2026

## Kết luận từ dữ liệu này

Đầu vào XYZ → pose/wrist và phát lại feature → quyết định khớp với app trên bản ghi. Vấn đề nhận diện từ vẫn còn: không có sự kiện chốt, và toàn bộ 34 lần suy luận thực sự đều có lý do từ chối `score`. Vì vậy không nên tiếp tục giảm dwell để xử lý riêng bản ghi này. Hướng ưu tiên chuyển sang kiểm tra/xử lý xếp hạng từ và cách kết hợp hai model, đồng thời xử lý một hiện tượng dò nhầm khi nghỉ như một lỗi riêng.

Không chứng minh pipeline đúng trên mọi thiết bị, không đo độ chính xác trên người mới, và không chứng minh mọi lỗi đều do model. Kiểm tra feature dùng lại context mặt đã ghi; chưa kiểm lại pixel → face anchor. Ảnh chỉ lấy mẫu mỗi 2 giây, không thay thế video liên tục.

## Nguồn và kiểm tra

- Nguồn: `C:\Users\Phuoc Tue\Downloads\signvoice-camera-diagnostic (1).json`, 10.383.808 byte.
- SHA-256: `e1ba71551e4127463209ef86c7aadfd129876f89583a6859f824f9cfd23be342`.
- Đúng mode `words`, đúng model 181 từ đang dùng; TCN và embedding hiện vẫn cùng tham gia với trọng số 50/50. Không phải chỉ có TCN.
- 14 PNG 640×480; đầu vào worker từ 0,947 đến 28,581 giây. Client/worker journal và phần PNG đều không báo cắt; không có worker overrun.
- 206/206 mẫu tính lại từ XYZ qua foreground filter, tracker và chuẩn hóa khớp trong dung sai tuyệt đối `2e-5`.
- 206/206 batch phát lại giữ nguyên scores/decisions/events, dung sai scores `atol=2e-5`, `rtol=5e-4`; sự kiện/nhãn phải khớp chính xác.
- 94 candidate sequences đối chiếu hàm chuẩn bị sequence với desktop: không có pose/wrist khác nhau; 4 lần mặt nạ quan sát được sửa nhưng không đổi pose/wrist. Desktop script vẫn có head/runtime khác, nên đây không phải chứng minh chạy toàn bộ desktop sẽ cho kết quả giống app.
- CPU IMAGE và browser VIDEO tìm cùng số tay ở 13/14 ảnh. Với 10 cặp bàn tay ghép được, trung vị của sai lệch XY trung vị từng tay khoảng 5,06 pixel. Đây là độ bất đồng giữa hai cách chạy, không phải sai số so với tọa độ chuẩn.

## Vì sao không chốt

Có 34 lần gọi model thực sự; không đếm lặp `inference_ran` còn lưu trong các snapshot worker cũ. Cả 34 bị chặn bởi score, 27 còn bị chặn bởi margin và 1 còn có `pair_or_motion`; các nhóm lý do có thể cùng xuất hiện. Không có candidate sẵn sàng chốt. Điểm selected head cao nhất là 0,575448 ở 15,076 giây, dưới ngưỡng 0,60.

| Từ muốn quan sát | Điểm cao nhất sau smoothing | Thời điểm đầu đạt đỉnh | Nhãn đứng đầu ở thời điểm đó |
|---|---:|---:|---|
| chào | 0,154757 | 5,236 s | biết |
| nghe | 0,013839 | 9,381 s | hâm mộ |
| nhìn | 0,544501 | 15,076 s | nhìn |
| rau | 0,406197 | 27,877 s | rau |

Đây là đỉnh của từng nhãn trên cả bản ghi, không phải accuracy hoặc xác suất đúng. Trình tự chào → nghe → nhìn → rau là trình tự đã yêu cầu khi ghi; ảnh lấy mẫu phù hợp các giai đoạn đó nhưng chưa có chú giải ký hiệu/thời gian độc lập. Không dùng bảng này để chỉnh ngưỡng theo từng từ.

Một số bất đồng trên **cùng cửa sổ đã được head gốc chọn**:

- 4,965 s: TCN xếp chào đầu với 0,295; embedding xếp biết đầu; hợp nhất xếp chào thứ hai với 0,239. Không chỉ là lỗi từ chối sau khi đã xếp đúng.
- 9,108 s: hợp nhất xếp hâm mộ đầu với 0,5625; TCN xếp nghe thứ hai nhưng điểm chỉ 0,0263, embedding xếp nghe thứ 15. Chỉ tăng trọng số embedding không giải quyết được trường hợp này.
- 15,076 s: embedding xếp nhìn đầu với 0,8341, TCN cũng xếp nhìn đầu nhưng chỉ 0,3168; hợp nhất còn 0,5754. Có dấu hiệu hai nhánh có độ tự tin khác nhau, cần đánh giá calibration.
- 24,324 s: TCN xếp rau đầu với 0,7531, embedding ưu tiên dừng lại với 0,7045; hợp nhất rau đầu nhưng chỉ 0,41265 và margin thấp.

Điểm của một cửa sổ khác với điểm sau smoothing. Không so trực tiếp cosine với softmax. Chốt nhầm hâm mộ có điểm cửa sổ gần điểm nhìn đúng; hạ một ngưỡng toàn cục không tách hai trường hợp một cách có bảo đảm. Chưa chạy policy mới trên bản ghi này.

## Lỗi dò tay tách riêng

Tại PNG 19,221 s, 21 landmark browser tập trung trên vùng tai, không thấy bàn tay tương ứng trong ảnh; CPU IMAGE không phát hiện tay. Browser giữ một track từ khoảng 18,5 s và sinh các cửa sổ dự đoán khi người dùng có vẻ đang nghỉ. Không có sự kiện chốt từ đoạn này.

Không gán nó làm nguyên nhân mất rau: các cửa sổ rau được chọn tại 23,429–24,868 s bắt đầu 22,532 s hoặc muộn hơn; các cửa sổ sau 26,965 s bắt đầu 26,277 s hoặc muộn hơn. Các cửa sổ này không chứa timestamp 19,221 s. Có thể kiểm tra tác động gián tiếp lên tracker trong thí nghiệm riêng, nhưng chưa làm và chưa kết luận.

Hai ảnh 23,269 và 26,277 s đều có hai tay ở browser và CPU. Không có đủ ảnh liên tục để đo recall hai tay hay mức mất track trong toàn bộ ký hiệu. Các frame không thấy tay ở tư thế nghỉ không được tự động tính là lỗi detector. Tổng số reject của bộ lọc client là 0 trên các preview có metadata; điều này không chứng minh không có false detection.

## Độ trễ trong lúc ghi PNG

Median/p95: dò local 49,5/73,3 ms; JPEG encode 90,95/178,96 ms; gửi ảnh → phản hồi đầu tiên 20/46,9 ms; phản hồi → UI frame 14/24 ms. Các công đoạn chồng nhau, không cộng p95. Đây không phải benchmark không ghi ảnh hoặc điện thoại thật; không so trực tiếp để tuyên bố nhanh/chậm hơn phiên khác. FPS local trung vị được báo khoảng 15,59.

## Hướng phát triển tiếp, theo thứ tự

1. Giữ model/policy hiện tại và khóa đường trích xuất làm đối chứng. Dừng thay camera hoặc dwell theo suy đoán; chỉ sửa nếu có bằng chứng mới. Bản ghi này phục vụ phát triển, không đưa vào audit/TEST.
2. Làm một phép kiểm offline có giới hạn cho **calibration của cặp model mới đồng bộ (encoder/prototype/TCN) và fusion**, so với cặp đang dùng. Cặp mới trước đó chỉ được thử ở một điểm fusion chuyển giao, chưa được calibration riêng. Áp dụng cùng quy tắc cho toàn bộ từ có dữ liệu. Tái dùng cache và split đã xác minh; loại mọi audit của giao thức mới ra trước khi đọc feature, không gộp epoch VAL vào calibration. Các tập đã dùng nhiều lượt chỉ là dữ liệu phát triển; không gọi chúng là TEST độc lập. Chốt trước số ít cấu hình nhiệt độ/trọng số; giữ nguyên score/margin/dwell để tách tác dụng của fusion. Đánh giá toàn bộ stream, không chỉ các cửa sổ đẹp hoặc bốn từ này. So với baseline cùng cadence 0,25 s và cùng buffer/gap. Báo macro recall, số đúng/sai/không chốt, sự kiện sai, gained/lost theo từ, kiểm tra cặp và độ phủ. Từ không có mẫu phải ghi chưa đo. Đây là phép phát triển, chưa phải chọn policy để public.
3. Nếu xếp hạng vẫn sai ở cả hai nhánh như nghe, không tiếp tục quét trọng số để bù. Chuyển sang dữ liệu/huấn luyện: dùng cùng extractor, bổ sung mẫu webcam thực vào TRAIN và các đoạn nghỉ/chuyển động không ký, lấy cửa sổ theo luồng live. Kiểm tra nhãn/biến thể có bằng chứng độc lập; không đổi nhãn theo model. Không tái thử thêm body/kiến trúc chỉ từ kết quả riêng lẻ này, vì các lượt trước chưa cho tín hiệu nhất quán.
4. Với track trên tai khi nghỉ, xây kiểm tra kỹ thuật riêng về độ tin cậy/reacquisition; chạy lại cả cử chỉ sát tai/mặt và hai tay để bảo đảm không lọc mất nghe/nhìn. Không chặn mọi tay gần mặt và không đặt luật riêng cho từng từ. Đừng bật IMAGE recovery mỗi frame nếu chưa đo chi phí.
5. Thu nền thật và webcam độc lập song song, gắn signer/session và tách người khỏi TRAIN/calibration. Tập độc lập giữ kín đến khi khóa candidate; ưu tiên cả từ thiếu calibration, không chỉ bốn từ này. Nền thật vẫn thiếu nên chưa có cơ sở triển khai policy nới nhận hoặc hạ dwell.

Mục tiêu của bước 2 là quyết định liệu fusion có vấn đề có thể sửa bằng calibration hay phải chuyển hẳn sang bổ sung dữ liệu và train. Không cam kết một bộ ngưỡng hay model khác sẽ nhận đúng toàn bộ 181 từ.

## Tệp kết quả

Trong `.runtime/camera-input-20261022/`: `input-report.json`, `components.json`, `summary.json`, `prediction-timeline.csv`, `contact-sheet.jpg` và các PNG có overlay. Ảnh chứa người/không gian thật, chỉ lưu cục bộ và không đưa vào Git.

Không đổi code nhận diện, model, policy, service, public hoặc notebook trong lần phân tích này.
