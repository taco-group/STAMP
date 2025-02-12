222#!/bin/bash

set -e

cuda=$1
work_dir=task_agnostic
adapter_list=("convnext")
modality_list=("m1" "m2" "m3" "m4")

cp -r "/home/xiangbog/Folder/AdapterCAV/opencood/hypes_yaml/opv2v/MoreModality/$work_dir" \
    "/home/xiangbog/Folder/AdapterCAV/opencood/logs/"



for modality in "${modality_list[@]}"; do
    CUDA_VISIBLE_DEVICES=$1 \
    python opencood/tools/train.py \
        -y None \
        --model_dir "opencood/logs/$work_dir/local/$modality"
done

CUDA_VISIBLE_DEVICES=$1 \
python opencood/tools/train.py \
    -y None \
    --model_dir "opencood/logs/$work_dir/protocol" \
    > "opencood/logs/$work_dir/protocol/train.log" 2>&1

source_dir="opencood/logs/$work_dir/protocol"
file=$(find "$source_dir" -type f -name "net_epoch_bestval_at*.pth" | head -n 1)
if [ -z "$file" ]; then
  echo "Best checkpoint of protocol not found. Make sure training the protocol model first."
  exit 1
fi

target_file_adapter="opencood/logs/$work_dir/local_adapter/protocol.pth"
cp "$file" "$target_file_adapter"
echo "$file has been copied and renamed to $target_file_adapter"



# Create symbolic links for each adapter and modality
for adapter in "${adapter_list[@]}"; do
    for modality in "${modality_list[@]}"; do
        mkdir -p "/home/xiangbog/Folder/AdapterCAV/opencood/logs/$work_dir/local_adapter/${adapter}/${modality}"
        ln -s "/home/xiangbog/Folder/AdapterCAV/opencood/logs/$work_dir/local_adapter/protocol.pth" \
            "/home/xiangbog/Folder/AdapterCAV/opencood/logs/$work_dir/local_adapter/${adapter}/${modality}/protocol.pth"
    done
done

for modality in "${modality_list[@]}"; do
    # Copy files for each adapter and modality
    source_dir="opencood/logs/$work_dir/local/$modality"
    
    file=$(find "$source_dir" -type f -name "net_epoch_bestval_at*.pth" | head -n 1)
    if [ -z "$file" ]; then
        echo "Best checkpoint of $modality not found. Make sure training the $modality model first."
        exit 1
    fi

    for adapter in "${adapter_list[@]}"; do
        target_file_adapter="opencood/logs/$work_dir/local_adapter/${adapter}/${modality}/ego.pth"
        cp "$file" "$target_file_adapter"
        echo "$file has been copied and renamed to $target_file_adapter"
    done
done



for adapter in "${adapter_list[@]}"; do
    for modality in "${modality_list[@]}"; do
        CUDA_VISIBLE_DEVICES=$1 \
        python opencood/tools/train_adapter.py \
            -y None \
            --model_dir "opencood/logs/$work_dir/local_adapter/$adapter/$modality" \
            > "opencood/logs/$work_dir/local_adapter/$adapter/$modality/train.log" 2>&1
    done
done


for adapter in "${adapter_list[@]}"; do
    python opencood/tools/merge_model_w_adapter.py \
        --model_dir "opencood/logs/$work_dir" \
        --adapter_dir $adapter
done


for adapter in "${adapter_list[@]}"; do
    for dir in "opencood/logs/$work_dir/final_infer/$adapter"/*/; do
        dir=${dir%*/}
        if [ -d "$dir" ]; then
            ln -s "/home/xiangbog/Folder/AdapterCAV/opencood/logs/$work_dir/final_infer/$adapter/net_epoch1.pth" \
                "/home/xiangbog/Folder/AdapterCAV/$dir/net_epoch1.pth"
        fi
    done
done

for adapter in "${adapter_list[@]}"; do
    for dir in "opencood/logs/$work_dir/final_infer/$adapter"/*/; do
        dir=${dir%*/}
        
        CUDA_VISIBLE_DEVICES=$1 \
        python opencood/tools/inference_heter_task.py \
            --model_dir "$dir" \
            --fusion_method intermediate \
            --range "51.2,51.2" \
            --task "segmentation" \
            --show_bev \
            > "$dir/inference.log" 2>&1

    done
done
