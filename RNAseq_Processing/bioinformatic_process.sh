#!/bin/bash

# Copy files from S3 to the local directory
aws s3 cp s3://tgsaraparra/SRR21849068/ /Datos/Sara/rawseq/SRR21849068/ --recursive

# Initial FastQC quality assessment
fastqc /Datos/Sara/rawseq/SRR21849068/* --outdir /Datos/Sara/fastqc/

# Variables
input_1="/Datos/Sara/rawseq/SRR21849068/Z15417A1_1.fq.gz"
input_2="/Datos/Sara/rawseq/SRR21849068/Z15417A1_2.fq.gz"
output_trimmed_1="/Datos/Sara/trimmedReads/Z15417A1_1.fq.gz"
output_trimmed_2="/Datos/Sara/trimmedReads/Z15417A1_2.fq.gz"
star_output_prefix="/Datos/Sara/starAligned/SRR21849068"
genome_dir="/media/carolinacastano/Datos 2/Data/starIndex/"
gtf_file="/media/carolinacastano/Datos 2/Data/ncbi_dataset/data/GCF_000001405.40/genomic.gtf"
output_counts="/Datos/Sara/readCounts/readCounts.txt"

# 1. Read trimming and filtering with Cutadapt
echo "Starting read trimming with Cutadapt..."
cutadapt -q 30 --max-n 0 -m 40 \
    -o "$output_trimmed_1" \
    -p "$output_trimmed_2" \
    "$input_1" "$input_2"

# Delete raw reads after successful trimming
if [ -f "$output_trimmed_1" ] && [ -f "$output_trimmed_2" ]; then
    echo "Trimming completed. Deleting raw read files..."
    rm "$input_1" "$input_2"
else
    echo "Trimming failed. Raw read files were not deleted."
fi

# 2. FastQC quality assessment of trimmed reads
fastqc /Datos/Sara/trimmedReads/* --outdir /Datos/Sara/fastqc_clean

# Set the open-file limit
ulimit -n 10000

# 3. Read alignment with STAR
# Alignment with STAR
echo "Starting alignment with STAR..."
STAR --runThreadN 32 \
    --genomeLoad LoadAndKeep \
    --genomeDir "$genome_dir" \
    --chimSegmentMin 12 \
    --chimOutType Junctions \
    --readFilesCommand zcat \
    --readFilesIn "$output_trimmed_1" "$output_trimmed_2" \
    --outFileNamePrefix "$star_output_prefix" \
    --limitBAMsortRAM 80000000000 \
    --outSAMtype BAM SortedByCoordinate \
    --outReadsUnmapped Fastx

# Delete trimmed reads after successful alignment
if [ -f "${star_output_prefix}Aligned.sortedByCoord.out.bam" ]; then
    echo "Alignment completed. Deleting trimmed read files..."
    rm "$output_trimmed_1" "$output_trimmed_2"
else
    echo "Alignment failed. Trimmed read files were not deleted."
fi

# 4. Read counting with featureCounts
echo "Starting read counting with featureCounts..."
featureCounts -T 8 -p --countReadPairs \
    -t exon -g gene_id \
    -a "$gtf_file" \
    -o "$output_counts" \
    /Datos/Sara/starAligned/*.sortedByCoord.out.bam > counts.log

# Delete aligned reads after successful counting
if [ -f "$output_counts" ]; then
    echo "Read counting completed. Deleting aligned read files..."
    rm /Datos/Sara/starAligned/*.sortedByCoord.out.bam
else
    echo "Read counting failed. Aligned read files were not deleted."
fi

# Upload read count results to S3
aws s3 cp "$output_counts" s3://tgsaraparra

echo "Deleting and recreating directories..."
rm -r /Datos/Sara/readCounts
mkdir /Datos/Sara/readCounts
rm -r /Datos/Sara/starAligned/
mkdir /Datos/Sara/starAligned

echo "Processing completed."

